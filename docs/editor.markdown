DMTL editor state 
=================

This work-in-progress document describes the DMTL editor state and the set of actions supported for manipulating and querying this state.

There are two parts to the editor state:

* Roughly, the abstract syntax tree (AST) of a DMTL module (a collection of function and type declarations), where some expressions can be _unfilled cells_ or _holes_. For short I'll just call this the _AST_. 
* The _context_, from which autocomplete suggestions are drawn. The context includes all the values defined in the currently edited module, and also any other values imported from global scope. 

Together, the AST + context form the _editor state_. There are operations for querying and transforming the context, and operations for querying and transforming the AST. The UI will work with a fairly abstract interface to the editor state. 

As a straw man, I'll indicate holes in the AST with `?` when giving editor program fragments. Here's an example editor state:

    foo x = x + ?
    bar2 = z + z
    z = ?

`?` indicates a hole. Each hole has a type, known to the DMTL compiler. 

We still have to work out exactly what the interface for this state looks like, but this is the basic idea. Some general questions - how will the UI indicate to the compiler what node in the AST it is refering to when it tells the editor state to make some internal transformation?

Aside: holes are not named; there is no way to indicate that two holes should be bound to the same value. We establish linkages between holes just by declaring a new variable (in this example, `z`), bound to a hole, and then referencing that variable in multiple places. 

Aside: the editor state may be a DMTL module, along with some distinguished expression. This would be applicable if the user is editing a particular hole and breaks this out into a separate editor pane. 

Possible operations
-------------------

Here are some possible operations for querying and transforming the editor state:

The context, `C`: 

* `import Name as LocalName`: add an expression or type to the context, giving it some local name
* `autoimport LocalName`: give a list of possible imports for a given (unqualified) local name 
* `unimport LocalName`: remove the import associated with the given `LocalName`
* `complete Type Pattern`: give a list of terms matching the given pattern and Type

The AST, `S`:

* `typeOf : (S, Loc) => Type` ask for the type of any location in the editor. A location may refer to a hole, or a filled cell
* `infer : (S,Term) => (Type,S)` ask for the type for a literal term
* `matches : (Type,Type) => Boolean` true if all values of the first type are considered an instance of the second type 
* `replace : (S, Loc, Term) => Result[S]` fill in a hole or replace a cell with a new value 
* `collapse : (S, Loc) => Result[(Term,S)]` -  
* `expand: (S, Loc) => Result[S]`
* `eval : (S, Term) => Result[(Term, S)]`  

* declare a new binding - binding is attached to some parent, becomes a let declaration, unless at top level

all expressions begin as a hole

given an expression, `e`, type-permitting, can go to: 

* `e ?`, `e ? ?`, `e ? ? ?`, etc - assuming `e` is a function, arguments become holes
* `? e`, `? ? e`, `? ? ? e`, `? e ?`, etc - assuming `e` is an argument to some function 
* `e2`, where `e2` has a matching type as `e`

other edits:

* given a declaration `f x = ?`, can add or remove parameters from `f` so long as this preserves compilation
* can rename a declaration, or one of its parameters
* can delete an unused declaration
* can substitute usages of a declaration with the declaration body, with confirmation
* can extract method
* can apply some transformation to the arg list of a function (swapping args, etc)

Modifying selections:

* All selections start at the leaf level
* Given a selection, can expand to parent expression, can move to left or right sibling, or can move down to first child
  * so, given a selection of `f [x] (g 12)`, where `[]` indicates what is selected - 
    * left: `[f] x (g 12)`
    * right: `f x [(g 12)]`
    * up: `[f x (g 12)]`
    * given `f x [(g 12)]`, down transitions to `f x ([g] 12)`
