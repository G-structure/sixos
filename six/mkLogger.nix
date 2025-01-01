{ six
, ...
}@args:

six.mkFunnel (
  (builtins.removeAttrs args [ "mkFunnel" ])
)
