# Don't spellcheck comments in asdiidocs
syn match asciidocCommentLine "^//\([^/].*\|\)$" contains=asciidocToDo,@NoSpell
