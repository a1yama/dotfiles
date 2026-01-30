th = th or {}
th.git = th.git or {}
th.git.modified_sign = "M "
th.git.added_sign = "A "
th.git.deleted_sign = "D "
th.git.untracked_sign = "? "
th.git.updated_sign = "U "
th.git.ignored_sign = "I "
th.git.clean_sign = ""
th.git.unknown_sign = ""

return require("git"):setup { order = 1500 }
