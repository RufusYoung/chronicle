# Archive

本目录保存已经完成引用审计、但不应继续参与当前 Demo 运行的历史内容。

- `legacy_project_copy/`：嵌套的旧 Godot 项目副本。
- `damaged_or_legacy_scripts/`：损坏或已被替代的旧脚本。
- `old_experiments/`：未挂载到当前入口的旧实验代码。
- `unused_code/`：预留给后续确认无运行引用的代码。
- `unused_docs/`：预留给不属于长期文档结构的旧文档。

本目录不是删除区。恢复时应先检查目标路径是否冲突，再将文件移回原路径并重新执行引用验证。

`.gdignore` 用于防止 Godot 扫描归档中的旧项目和损坏脚本。
