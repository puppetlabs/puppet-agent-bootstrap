require 'puppet/application/face_base'
require 'puppet/ssl/oids'

class Puppet::Application::Bootstrap < Puppet::Application::FaceBase
  def app_defaults
    super.merge({
      :catalog_terminus => :rest,
      :catalog_cache_terminus => :json,
      :node_terminus => :rest,
      :facts_terminus => :facter,
    })
  end

  def setup
    super

    Puppet::SSL::Oids.register_puppet_oids
    Puppet::SSL::Host.ca_location = :none if Gem::Version.new(Puppet.version) < Gem::Version.new('6.0')
    Puppet.settings.preferred_run_mode = "agent"
    Puppet.settings.use(:ssl)
  end
end
