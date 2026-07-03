use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

use crate::domain::{AppError, AppResult};

/// 将简单枚举（serde snake_case 的 unit 变体）编码为字符串列值。
pub fn enum_to_str<T: Serialize>(value: &T) -> AppResult<String> {
    match serde_json::to_value(value) {
        Ok(Value::String(s)) => Ok(s),
        Ok(other) => Err(AppError::database(format!("枚举编码异常: {other}"))),
        Err(e) => Err(AppError::database(format!("枚举序列化失败: {e}"))),
    }
}

/// 从字符串列值还原简单枚举。
pub fn enum_from_str<T: DeserializeOwned>(s: &str) -> AppResult<T> {
    serde_json::from_value(Value::String(s.to_string()))
        .map_err(|e| AppError::database(format!("枚举反序列化失败({s}): {e}")))
}

/// 可空枚举编码。
pub fn opt_enum_to_str<T: Serialize>(value: &Option<T>) -> AppResult<Option<String>> {
    match value {
        Some(v) => Ok(Some(enum_to_str(v)?)),
        None => Ok(None),
    }
}

/// 可空枚举还原。
pub fn opt_enum_from_str<T: DeserializeOwned>(s: Option<String>) -> AppResult<Option<T>> {
    match s {
        Some(s) => Ok(Some(enum_from_str(&s)?)),
        None => Ok(None),
    }
}

/// 将 `Vec`/`HashMap` 等编码为 JSON 字符串（用于 `*_json` 列）。
pub fn json_encode<T: Serialize>(value: &T) -> AppResult<String> {
    serde_json::to_string(value).map_err(|e| AppError::database(format!("JSON 编码失败: {e}")))
}

/// 从 JSON 字符串还原（用于 `*_json` 列）。
pub fn json_decode<T: DeserializeOwned>(s: &str) -> AppResult<T> {
    serde_json::from_str(s).map_err(|e| AppError::database(format!("JSON 解码失败: {e}")))
}
