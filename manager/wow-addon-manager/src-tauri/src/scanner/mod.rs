//! Addon scanner & .toc parser (A2)。

pub mod addon_scanner;
pub mod toc_parser;

pub use addon_scanner::scan_addons;
pub use toc_parser::{find_primary_toc, parse_toc_content, parse_toc_file};
