module Text.DescriptorProtos.ServiceOptions
  (ServiceOptions(..))
 where

import Text.ProtocolBuffers.Header

data ServiceOptions = ServiceOptions
  deriving (Show,Eq,Ord,Typeable)

$( derive makeMonoid ''ServiceOptions )

instance OptionFlag a => Monoid (Option a ServiceOptions) where mempty = Absent; mappend = op'Merge

instance Default ServiceOptions where