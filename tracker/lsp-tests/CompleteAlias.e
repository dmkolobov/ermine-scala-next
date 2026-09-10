module CompleteAlias where

import Bool as B
import Maybe using isJust

aliasValue = not_B True

usesJust = isJust
