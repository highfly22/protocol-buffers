module Text.DescriptorProtos.MethodOptions
  (MethodOptions(..))
 where

import Text.ProtocolBuffers.Header

data MethodOptions = MethodOptions
  deriving (Show,Eq,Ord,Typeable)

$( derive makeMonoid ''MethodOptions )

instance OptionFlag a => Monoid (Option a MethodOptions) where mempty = Absent; mappend = op'Merge

instance Default MethodOptions where