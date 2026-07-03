use std::path::PathBuf;
use std::sync::Mutex;

use rusqlite::Connection;

use crate::domain::{AppError, AppResult};
use crate::infra::db::migrations::run_migrations;

/// SQLite 连接封装。打开时自动执行幂等迁移到最新 schema。
pub struct Database {
    conn: Mutex<Connection>,
    path: PathBuf,
}

impl Database {
    /// 在指定路径打开（或创建）数据库文件，并执行迁移。
    pub fn open(path: PathBuf) -> AppResult<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| AppError::database(format!("创建数据库目录失败: {e}")))?;
        }
        let conn = Connection::open(&path)
            .map_err(|e| AppError::database(format!("打开数据库失败: {e}")))?;
        run_migrations(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            path,
        })
    }

    /// 用于测试/健康检查的内存数据库（同样执行迁移）。
    pub fn open_in_memory() -> AppResult<Self> {
        let conn = Connection::open_in_memory()
            .map_err(|e| AppError::database(format!("打开内存数据库失败: {e}")))?;
        run_migrations(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            path: PathBuf::from(":memory:"),
        })
    }

    pub fn path(&self) -> &PathBuf {
        &self.path
    }

    /// 健康检查：执行一次最简查询确认连接可用。
    pub fn is_ready(&self) -> bool {
        let guard = match self.conn.lock() {
            Ok(g) => g,
            Err(_) => return false,
        };
        guard
            .query_row("SELECT 1", [], |row| row.get::<_, i64>(0))
            .is_ok()
    }

    /// 以只读/普通方式使用连接。
    pub fn with_connection<T>(
        &self,
        f: impl FnOnce(&Connection) -> AppResult<T>,
    ) -> AppResult<T> {
        let guard = self
            .conn
            .lock()
            .map_err(|_| AppError::database("数据库连接锁获取失败"))?;
        f(&guard)
    }

    /// 在事务中执行，闭包返回 `Ok` 则提交，`Err` 则回滚。
    pub fn with_transaction<T>(
        &self,
        f: impl FnOnce(&rusqlite::Transaction<'_>) -> AppResult<T>,
    ) -> AppResult<T> {
        let mut guard = self
            .conn
            .lock()
            .map_err(|_| AppError::database("数据库连接锁获取失败"))?;
        let tx = guard
            .transaction()
            .map_err(|e| AppError::database(format!("开启事务失败: {e}")))?;
        let result = f(&tx)?;
        tx.commit()
            .map_err(|e| AppError::database(format!("提交事务失败: {e}")))?;
        Ok(result)
    }
}
