module Layout.PresRow where 

import Constraint 
import Function using flip ; ($)

import Layout.Presentation using type Presentation ; asPresentation

foreign 

  data "com.clarifi.reporting.writers.PresRow" PresRow (r : rho)
  
  function "com.clarifi.reporting.writers.PresRow" "empty"
    empty# : PresRow (||)

  method "cons" 
    cons# : RUnion2 r' r ra 
         => PresRow r 
         -> Presentation ra a
         -> PresRow r'

empty_Bracket : PresRow (||)
empty_Bracket = empty#  

cons_Bracket : (AsPresentation o , RUnion2 r' r ra) 
            => o ra a 
            -> PresRow r 
            -> PresRow r'
cons_Bracket p = flip cons# (asPresentation p)