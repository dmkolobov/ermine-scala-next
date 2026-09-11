module Tab where

import Bool

-- TICKET E8.  A tab is ONE character of source text and SEVEN columns' worth
-- of parser column (`scalaparsers.Pos.bump` sends column 1 to column 8), while
-- an LSP position counts characters -- so a name at the head of a tab-indented
-- line below sits at CHARACTER 1 and at PARSER COLUMN 8, and before 7.5 every
-- range this server published for one was seven characters to the right of the
-- text it named.
tabbed = go where
	go = True

use = tabbed

-- An UNDEFINED NAME behind a tab.  Its note carries no span, so the position
-- is recovered from the report's own `file:line:col:` prefix -- and that column
-- is a parser column too.
missing =
	nosuch

-- An UNKNOWN OPERATOR behind a tab: a structured READ diagnostic, which is the
-- other way a range reaches the editor.
huh =
	True <+> False
