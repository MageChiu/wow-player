use serde::{Deserialize, Serialize};

/// `.toc` 文件解析结果（设计规划 §11.3）。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TocMetadata {
    pub interface_version: Option<String>,
    pub title: Option<String>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub notes: Option<String>,
    pub dependencies: Vec<String>,
    pub optional_dependencies: Vec<String>,
    pub saved_variables: Vec<String>,
    pub saved_variables_per_character: Vec<String>,
}
