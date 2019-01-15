module Optics.Internal.IxTraversal where

import Optics.Internal.Indexed
import Optics.Internal.Optic
import Optics.Internal.Profunctor

-- | Type synonym for a type-modifying indexed traversal.
type IxTraversal i s t a b = Optic A_Traversal '[i] s t a b

-- | Type synonym for a type-preserving indexed traversal.
type IxTraversal' i s a = Optic' A_Traversal '[i] s a

-- | Explicitly cast an optic to an indexed traversal.
toIxTraversal
  :: Is k A_Traversal
  => Optic k '[i] s t a b
  -> IxTraversal i s t a b
toIxTraversal = sub
{-# INLINE toIxTraversal #-}

-- | Build an indexed traversal from the van Laarhoven representation.
ixTraversalVL
  :: (forall f. Applicative f => (i -> a -> f b) -> s -> f t)
  -> IxTraversal i s t a b
ixTraversalVL t = Optic (iwander t)
{-# INLINE ixTraversalVL #-}

-- | Indexed traversal via the 'TraversableWithIndex' class.
--
-- >>> iover (icompose (,) $ itraversed % itraversed) (,) ["ab", "cd"]
-- [[((0,0),'a'),((0,1),'b')],[((1,0),'c'),((1,1),'d')]]
--
itraversed
  :: TraversableWithIndex i t
  => IxTraversal i (t a) (t b) a b
itraversed = ixTraversalVL itraverse
{-# INLINE itraversed #-}

itraverseOf
  :: (CheckIndices i is, Is k A_Traversal)
  => Optic k is s t a b
  -> (forall f. Applicative f => (i -> a -> f b) -> s -> f t)
itraverseOf o f = runIxStar (getOptic (toIxTraversal o) (IxStar f)) id
{-# INLINE itraverseOf #-}
