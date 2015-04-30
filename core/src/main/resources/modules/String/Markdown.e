module String.Markdown where

import String

bold s = "**" ++ s ++ "**"
italic s = "*" ++ s ++ "*"
link title loc = "[" ++ title "](" ++ loc ++ ")"

