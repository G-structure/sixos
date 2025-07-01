{ ... }:
{
  # Provide directories for readTree so it can discover hosts and tags.
  hosts = ./hosts;
  tags  = ./tags;
  subnets = {};
  overlay = (_: _: {});
} 