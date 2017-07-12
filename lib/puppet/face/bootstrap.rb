require 'puppet/face'
require 'puppet/ssl'

Puppet::Face.define(:bootstrap, '0.1.0') do
  copyright "Puppet", 2017
  summary "Initialize the Puppet agent"

  action(:csr) do
    summary "Initialize the agent key pair and save a CSR"

    when_invoked do |opts|
      Puppet::SSL::Oids.register_puppet_oids
      Puppet::SSL::Oids.load_custom_oid_file(Puppet[:trusted_oid_mapping_file])
      Puppet::SSL::Host.ca_location = :none
      Puppet.settings.preferred_run_mode = "agent"
      Puppet.settings.use(:ssl)

      Puppet::SSL::Host.localhost
    end
  end
end
