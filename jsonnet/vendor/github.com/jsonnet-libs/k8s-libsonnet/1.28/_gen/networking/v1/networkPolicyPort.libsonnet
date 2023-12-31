{
  local d = (import 'doc-util/main.libsonnet'),
  '#':: d.pkg(name='networkPolicyPort', url='', help='"NetworkPolicyPort describes a port to allow traffic on"'),
  '#withEndPort':: d.fn(help='"endPort indicates that the range of ports from port to endPort if set, inclusive, should be allowed by the policy. This field cannot be defined if the port field is not defined or if the port field is defined as a named (string) port. The endPort must be equal or greater than port."', args=[d.arg(name='endPort', type=d.T.integer)]),
  withEndPort(endPort): { endPort: endPort },
  '#withPort':: d.fn(help='"IntOrString is a type that can hold an int32 or a string.  When used in JSON or YAML marshalling and unmarshalling, it produces or consumes the inner type.  This allows you to have, for example, a JSON field that can accept a name or number."', args=[d.arg(name='port', type=d.T.string)]),
  withPort(port): { port: port },
  '#withProtocol':: d.fn(help='"protocol represents the protocol (TCP, UDP, or SCTP) which traffic must match. If not specified, this field defaults to TCP."', args=[d.arg(name='protocol', type=d.T.string)]),
  withProtocol(protocol): { protocol: protocol },
  '#mixin': 'ignore',
  mixin: self,
}
