-- |
-- Module: Optics.Label
-- Description: Overloaded labels as optics
--
-- Overloaded labels are a solution to Haskell's namespace problem for records.
-- The @-XOverloadedLabels@ extension allows a new expression syntax for labels,
-- a prefix @#@ sign followed by an identifier, e.g. @#foo@.  These expressions
-- can then be given an interpretation that depends on the type at which they
-- are used and the text of the label.
module Optics.Label
  ( -- * How to use labels as optics to make working with Haskell's records more convenient
    --
    -- ** The problem
    -- $problem

    -- ** The solution
    -- $solution

    -- ** The result
    -- $result

    -- * Sample usage
    -- $sampleUsage

    -- * Technical details

    -- ** 'LabelOptic' type class
    LabelOptic(..)
  , LabelOptic'

    -- ** Structure of 'LabelOptic' instances
    -- $instanceStructure

    -- ** Limitations arising from functional dependencies
    -- $fundepLimitations
  ) where

import Optics.Internal.Optic

-- $sampleUsage
--
-- #usage#
-- An example showing how overloaded labels can be used as optics.
--
-- >>> :set -XDataKinds
-- >>> :set -XDuplicateRecordFields
-- >>> :set -XFlexibleInstances
-- >>> :set -XMultiParamTypeClasses
-- >>> :set -XOverloadedLabels
-- >>> :set -XTypeFamilies
-- >>> :set -XUndecidableInstances
-- >>> :{
-- data Human = Human
--   { name :: String
--   , age  :: Integer
--   , pets :: [Pet]
--   } deriving Show
-- data Pet
--   = Cat  { name :: String, age :: Int, lazy :: Bool }
--   | Fish { name :: String, age :: Int }
--   deriving Show
-- :}
--
-- The following instances can be generated by @makeFieldLabelsWith
-- noPrefixFieldLabels@ from
-- @<https://hackage.haskell.org/package/optics-th/docs/Optics-TH.html Optics.TH>@
-- in the @<https://hackage.haskell.org/package/optics-th optics-th>@ package:
--
-- >>> :{
-- instance (k ~ A_Lens, a ~ String, b ~ String) => LabelOptic "name" k Human Human a b where
--   labelOptic = lensVL $ \f (Human name age pets) -> (\name' -> Human name' age pets) <$> f name
-- instance (k ~ A_Lens, a ~ Integer, b ~ Integer) => LabelOptic "age" k Human Human a b where
--   labelOptic = lensVL $ \f (Human name age pets) -> (\age' -> Human name age' pets) <$> f age
-- instance (k ~ A_Lens, a ~ [Pet], b ~ [Pet]) => LabelOptic "pets" k Human Human a b where
--   labelOptic = lensVL $ \f (Human name age pets) -> (\pets' -> Human name age pets') <$> f pets
-- instance (k ~ A_Lens, a ~ String, b ~ String) => LabelOptic "name" k Pet Pet a b where
--   labelOptic = lensVL $ \f s -> case s of
--     Cat  name age lazy -> (\name' -> Cat  name' age lazy) <$> f name
--     Fish name age      -> (\name' -> Fish name' age     ) <$> f name
-- instance (k ~ A_Lens, a ~ Int, b ~ Int) => LabelOptic "age" k Pet Pet a b where
--   labelOptic = lensVL $ \f s -> case s of
--     Cat  name age lazy -> (\age' -> Cat  name age' lazy) <$> f age
--     Fish name age      -> (\age' -> Fish name age'     ) <$> f age
-- instance (k ~ An_AffineTraversal, a ~ Bool, b ~ Bool) => LabelOptic "lazy" k Pet Pet a b where
--   labelOptic = atraversalVL $ \point f s -> case s of
--     Cat name age lazy -> (\lazy' -> Cat name age lazy') <$> f lazy
--     _                 -> point s
-- :}
--
-- Here is some test data:
--
-- >>> :{
-- peter :: Human
-- peter = Human { name = "Peter"
--               , age  = 13
--               , pets = [ Fish { name = "Goldie"
--                               , age  = 1
--                               }
--                        , Cat { name = "Loopy"
--                              , age  = 3
--                              , lazy = False
--                              }
--                        , Cat { name = "Sparky"
--                              , age  = 2
--                              , lazy = True
--                              }
--                        ]
--              }
-- :}
--
-- Now we can ask for Peter's name:
--
-- >>> view #name peter
-- "Peter"
--
-- or for names of his pets:
--
-- >>> toListOf (#pets % folded % #name) peter
-- ["Goldie","Loopy","Sparky"]
--
-- We can check whether any of his pets is lazy:
--
-- >>> orOf (#pets % folded % #lazy) peter
-- True
--
-- or how things might be be a year from now:
--
-- >>> peter & over #age (+1) & over (#pets % mapped % #age) (+1)
-- Human {name = "Peter", age = 14, pets = [Fish {name = "Goldie", age = 2},Cat {name = "Loopy", age = 4, lazy = False},Cat {name = "Sparky", age = 3, lazy = True}]}
--
-- Perhaps Peter is going on vacation and needs to leave his pets at home:
--
-- >>> peter & set #pets []
-- Human {name = "Peter", age = 13, pets = []}

-- $problem
--
-- Standard Haskell records are a common source of frustration amongst seasoned
-- Haskell programmers. Their main issues are:
--
-- (1) Inability to define multiple data types sharing field names in the same
--     module.
--
-- (2) Pollution of global namespace as every field accessor is also a top-level
--     function.
--
-- (3) Clunky update syntax, especially when nested fields get involved.
--
-- Over the years multiple language extensions were proposed and implemented to
-- alleviate these issues. We're quite close to having a reasonable solution
-- with the following trifecta:
--
-- - @<https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#extension-DuplicateRecordFields DuplicateRecordFields>@ - introduced in GHC 8.0.1, addresses (1)
--
-- - @<https://github.com/ghc-proposals/ghc-proposals/pull/160 NoFieldSelectors>@ - accepted GHC proposal, addresses (2)
--
-- - @<https://github.com/ghc-proposals/ghc-proposals/pull/282 RecordDotSyntax>@ - accepted GHC proposal, addresses (3)
--
-- It needs to be noted however that both @NoFieldSelectors@ and
-- @RecordDotSyntax@ are not yet implemented, with the latter depending on
-- adding @setField@ to @HasField@
-- (<https://gitlab.haskell.org/ghc/ghc/issues/16232 ghc/16232>), not yet
-- merged.
--
-- Is there no hope then for people who would like to work with records in a
-- reasonable way without waiting for these extensions? Not necessarily, as by
-- following a couple of simple patterns we can get pretty much the same (and
-- more) features with labels as optics, just with a slightly more verbose
-- syntax.

-- $solution
--
-- === Prefixless fields with @DuplicateRecordFields@
--
-- We necessarily want field names to be prefixless, i.e. @field@ to be a field
-- name and @#field@ to be an overloaded label that becomes an optic refering to
-- this field in the appropriate context.  With this approach we get working
-- autocompletion and jump-to-definition in editors supporting @ctags@/@etags@
-- in combination with @<https://hackage.haskell.org/package/hasktags hasktags>@,
-- both of which (especially the latter) are very important for developer's
-- productivity in real-world code bases.
--
-- Let's look at data types defined with this approach in mind:
--
-- @
-- {-\# LANGUAGE DuplicateRecordFields \#-}
--
-- import Data.Time
--
-- data User = User { id     :: Int
--                  , name   :: String
--                  , joined :: UTCTime
--                  , movies :: [Movie]
--                  }
--
-- data Movie = Movie { id          :: Int
--                    , name        :: String
--                    , releaseDate :: UTCTime
--                    }
-- @
--
-- Then appropriate 'LabelOptic' instances can be either written by hand or
-- generated using Template Haskell functions (defined in
-- @<https://hackage.haskell.org/package/optics-th/docs/Optics-TH.html Optics.TH>@
-- module from @<https://hackage.haskell.org/package/optics-th optics-th>@ package)
-- with
--
-- @
-- makeFieldLabelsWith noPrefixFieldLabels ''User
-- makeFieldLabelsWith noPrefixFieldLabels ''Movie
-- @
--
-- /Note:/ there exists a similar approach that involves prefixing field names
-- with the underscore and generation of lenses as ordinary functions so that
-- @_field@ is the ordinary field name and @field@ is the lens referencing
-- it. The drawback of such solution is inability to get working
-- jump-to-definition for field names, which makes navigation in unfamiliar code
-- bases significantly harder, so it's not recommended.
--
-- === Emulation of @NoFieldSelectors@
--
-- Prefixless fields (especially ones with common names such as @id@ or @name@)
-- leak into global namespace as accessor functions and can generate a lot of
-- name clashes. Before @NoFieldSelectors@ is available, this can be alleviated by
-- splitting modules defining types into two, namely:
--
-- (1) A private one that exports full type definitions, i.e. with their fields
--     and constructors.
--
-- (2) A public one that exports only constructors (or no constructors at all if
--     the data type in question is opaque).
--
-- There is no notion of private and public modules within a single cabal
-- target, but we can hint at it e.g. by naming the public module @T@ and
-- private @T.Internal@.
--
-- An example:
--
-- Private module:
--
-- @
-- {-\# LANGUAGE DataKinds \#-}
-- {-\# LANGUAGE FlexibleInstances \#-}
-- {-\# LANGUAGE MultiParamTypeClasses \#-}
-- {-\# LANGUAGE TemplateHaskell \#-}
-- {-\# LANGUAGE TypeFamilies \#-}
-- {-\# LANGUAGE UndecidableInstances \#-}
-- module User.Internal (User(..)) where
--
-- import Optics.TH
--
-- data User = User { id   :: Int
--                  , name :: String
--                  }
--
-- makeFieldLabelsWith noPrefixFieldLabels ''User
--
-- ...
-- @
--
-- Public module:
--
-- @
-- module User (User(User)) where
--
-- import User.Internal
--
-- ...
-- @
--
-- Then, whenever we're dealing with a value of type @User@ and want to read or
-- modify its fields, we can use corresponding labels without having to import
-- @User.Internal@. Importing @User@ is enough because it provides appropriate
-- 'LabelOptic' instances through @User.Internal@ which enables labels to be
-- interpreted as optics in the appropriate context.
--
-- /Note:/ if you plan to completely hide (some of) the fields of a data type,
-- you need to skip defining the corresponding 'LabelOptic' instances for them
-- (in case you want fields to be read only, you can make the optic kind of the
-- coresponding 'LabelOptic' 'A_Getter' instead of 'A_Lens'). It's because
-- Haskell makes it impossible to selectively hide instances, so once a
-- 'LabelOptic' instance is defined, it'll always be possible to use a label
-- that desugars to its usage whenever a module with its definition is
-- (transitively) imported.
--
-- @
-- {-\# LANGUAGE OverloadedLabels #-}
--
-- import Optics
-- import User
--
-- greetUser :: User -> String
-- greetUser user = "Hello " ++ user ^. #name ++ "!"
--
-- addSurname :: String -> User -> User
-- addSurname surname user = user & #name %~ (++ " " ++ surname)
-- @
--
-- But what if we want to create a new @User@ with the record syntax? Importing
-- @User@ module is not sufficient since it doesn't export @User@'s
-- fields. However, if we import @User.Internal@ /fully qualified/ and make use
-- of the fact that field names used within the record syntax don't have to be
-- prefixed when @DisambiguateRecordFields@ language extension is enabled, it
-- works out:
--
-- @
-- {-\# LANGUAGE DisambiguateRecordFields \#-}
--
-- import User
-- import qualified User.Internal
--
-- newUser :: User
-- newUser = User { id   = 1     -- not User.Internal.id
--                , name = \"Ian\" -- not User.Internal.name
--                }
-- @
--
-- This way top-level field accessor functions stay in their own qualified
-- namespace and don't generate name clashes, yet they can be used without
-- prefix within the record syntax.

-- $result
--
-- When we follow the above conventions for data types in our application, we
-- get:
--
-- (1) Prefixless field names that don't pollute global namespace (with the
--     internal module qualification trick).
--
-- (2) Working tags based jump-to-definition for field names (as @field@ is the
--     ordinary field, whereas @#field@ is the lens referencing it).
--
-- (3) The full power of optics at our disposal, should we ever need it.

-- $instanceStructure
--
-- You might wonder why instances above are written in form
--
-- @
-- instance (k ~ A_Lens, a ~ [Pet], b ~ [Pet]) => LabelOptic "pets" k Human Human a b where
-- @
--
-- instead of
--
-- @
-- instance LabelOptic "pets" A_Lens Human Human [Pet] [Pet] where
-- @
--
-- The reason is that using the first form ensures that it is enough for GHC to
-- match on the instance if either @s@ or @t@ is known (as type equalities are
-- verified after the instance matches), which not only makes type inference
-- better, but also allows it to generate better error messages.
--
-- For example, if you try to write @peter & set #pets []@ with the appropriate
-- 'LabelOptic' instance in the second form, you get the following:
--
-- @
-- <interactive>:16:1: error:
--    • No instance for LabelOptic "pets" ‘A_Lens’ ‘Human’ ‘()’ ‘[Pet]’ ‘[a0]’
--        (maybe you forgot to define it or misspelled a name?)
--    • In the first argument of ‘print’, namely ‘it’
--      In a stmt of an interactive GHCi command: print it
-- @
--
-- That's because empty list doesn't have type @[Pet]@, it has type @[r]@ and
-- GHC doesn't have enough information to match on the instance we
-- provided. We'd need to either annotate the list: @peter & set #pets
-- ([]::[Pet])@ or the result type: @peter & set #pets [] :: Human@, which is
-- suboptimal.
--
-- Here are more examples of confusing error messages if the instance for
-- @LabelOptic "age"@ is written without type equalities:
--
-- @
-- λ> view #age peter :: Char
--
-- <interactive>:28:6: error:
--     • No instance for LabelOptic "age" ‘k0’ ‘Human’ ‘Human’ ‘Char’ ‘Char’
--         (maybe you forgot to define it or misspelled a name?)
--     • In the first argument of ‘view’, namely ‘#age’
--       In the expression: view #age peter :: Char
--       In an equation for ‘it’: it = view #age peter :: Char
-- λ> peter & set #age "hi"
--
-- <interactive>:29:1: error:
--     • No instance for LabelOptic "age" ‘k’ ‘Human’ ‘b’ ‘a’ ‘[Char]’
--         (maybe you forgot to define it or misspelled a name?)
--     • When checking the inferred type
--         it :: forall k b a. ((TypeError ...), Is k A_Setter) => b
--
-- λ> age = #age :: Iso' Human Int
--
-- <interactive>:7:7: error:
--     • No instance for LabelOptic "age" ‘An_Iso’ ‘Human’ ‘Human’ ‘Int’ ‘Int’
--         (maybe you forgot to define it or misspelled a name?)
--     • In the expression: #age :: Iso' Human Int
--       In an equation for ‘age’: age = #age :: Iso' Human Int
-- @
--
-- If we use the first form, error messages become more accurate:
--
-- @
-- λ> view #age peter :: Char
-- <interactive>:31:6: error:
--     • Couldn't match type ‘Char’ with ‘Integer’
--         arising from the overloaded label ‘#age’
--     • In the first argument of ‘view’, namely ‘#age’
--       In the expression: view #age peter :: Char
--       In an equation for ‘it’: it = view #age peter :: Char
-- λ> peter & set #age "hi"
--
-- <interactive>:32:13: error:
--     • Couldn't match type ‘[Char]’ with ‘Integer’
--         arising from the overloaded label ‘#age’
--     • In the first argument of ‘set’, namely ‘#age’
--       In the second argument of ‘(&)’, namely ‘set #age "hi"’
--       In the expression: peter & set #age "hi"
-- λ> age = #age :: Iso' Human Int
--
-- <interactive>:9:7: error:
--     • Couldn't match type ‘An_Iso’ with ‘A_Lens’
--         arising from the overloaded label ‘#age’
--     • In the expression: #age :: Iso' Human Int
--       In an equation for ‘age’: age = #age :: Iso' Human Int
-- @

-- $fundepLimitations #limitations#
--
-- 'LabelOptic' uses the following functional dependencies to guarantee good
-- type inference:
--
-- 1. @name s -> k a@ (the optic for the field @name@ in @s@ is of type @k@ and
-- focuses on @a@)
--
-- 2. @name t -> k b@ (the optic for the field @name@ in @t@ is of type @k@ and
-- focuses on @b@)
--
-- 3. @name s b -> t@ (replacing the field @name@ in @s@ with @b@ yields @t@)
--
-- 4. @name t a -> s@ (replacing the field @name@ in @t@ with @a@ yields @s@)
--
-- Dependencies (1) and (2) ensure that when we compose two optics, the middle
-- type is unambiguous. The consequence is that it's not possible to create
-- label optics with @a@ or @b@ referencing type variables not referenced in @s@
-- or @t@, i.e. getters for fields of rank 2 type or reviews for constructors
-- with existentially quantified types inside.
--
-- Dependencies (3) and (4) ensure that when we perform a chain of updates, the
-- middle type is unambiguous. The consequence is that it's not possible to
-- define label optics that:
--
-- - Modify phantom type parameters of type @s@ or @t@.
--
-- - Modify type parameters of type @s@ or @t@ if @a@ or @b@ contain ambiguous
--   applications of type families to these type parameters.

-- $setup
-- >>> import Optics.Core
