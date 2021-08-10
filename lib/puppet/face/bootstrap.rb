require 'puppet/face'
require 'puppet/ssl'

module PuppetX
  module Puppetlabs
    module Bootstrap
      def verify_signed_cert!(hostcert)
        if !hostcert.nil?
          Puppet.notice "Found a certificate for #{Puppet[:certname]}"
        else
          Puppet.err "No signed certificate found for #{Puppet[:certname]}"
          exit(1)
        end
      end

      def verify_ssl_files_match!(hostcert, hostkey)
        if hostcert.content.check_private_key(hostkey.content)
          Puppet.notice "Private key matches certificate"
        else
          Puppet.err "Signed certificate does not match host private key"
          exit(1)
        end
      end

      def verify_node_definition_reachable!
        Puppet::Node.indirection.find(Puppet[:node_name_value],
                                             environment: Puppet::Node::Environment.remote('production'),
                                             ignore_cache: true,
                                             fail_on_404: true)
        Puppet.notice("Contacted Puppet master for node definition")
      rescue => e
        Puppet.err "Unable to reach Puppet master: #{e.message}"
        exit(1)
      end

      def generate_csr
        Puppet.settings.use(:main, :ssl, :agent)
        name = Puppet[:certname]
        cert_provider = Puppet::X509::CertProvider.new
        key = cert_provider.load_private_key(name)
        unless key
          Puppet.info _("Creating a new RSA SSL key for %{name}") % { name: name }
          key = OpenSSL::PKey::RSA.new(Puppet[:keylength].to_i)
          cert_provider.save_private_key(name, key)
        end
        csr = cert_provider.create_request(name, key)
        cert_provider.save_request(name, csr)
      end

      def purge_certs
        paths = {
          'local CA certificate' => Puppet[:localcacert],
          'local CRL' => Puppet[:hostcrl],
          'private key' => Puppet[:hostprivkey],
          'public key'  => Puppet[:hostpubkey],
          'certificate request' => File.join(Puppet[:requestdir], "#{Puppet[:certname]}.pem"),
          'certificate' => Puppet[:hostcert],
          'private key password file' => Puppet[:passfile]
        }
        paths.each_pair do |label, path|
          if Puppet::FileSystem.exist?(path)
            Puppet::FileSystem.unlink(path)
            Puppet.notice _("Removed %{label} %{path}") % { label: label, path: path }
          end
        end
      end
    end
  end
end

Puppet::Face.define(:bootstrap, '0.1.0') do
  copyright "Puppet", 2017
  summary "Initialize the Puppet agent"

  action(:csr) do
    summary "Initialize the agent key pair and save a CSR"

    when_invoked do |opts|
      Puppet::SSL::Oids.register_puppet_oids
      Puppet::SSL::Oids.load_custom_oid_file(Puppet[:trusted_oid_mapping_file])
      if Gem::Version.new(Puppet.version) > Gem::Version.new('6.0')
        extend PuppetX::Puppetlabs::Bootstrap
        generate_csr
      else
        Puppet[:localcacert]
        Puppet[:hostcrl]
        Puppet::SSL::Host.localhost
      end
    end
  end

  action(:purge) do
    summary "Purge all agent SSL files"
    when_invoked do |opts|

      if Gem::Version.new(Puppet.version) > Gem::Version.new('6.0')
        extend PuppetX::Puppetlabs::Bootstrap
        purge_certs
      else
        Puppet.notice("Purging CA CRL")
        Puppet::SSL::CertificateRevocationList.indirection.destroy('ca')

        Puppet.notice("Purging agent certificate")
        Puppet::SSL::Certificate.indirection.destroy(Puppet[:certname])
        Puppet.notice("Purging agent certificate request")
        Puppet::SSL::CertificateRequest.indirection.destroy(Puppet[:certname])
        Puppet.notice("Purging agent key pair")
        Puppet::SSL::Key.indirection.destroy(Puppet[:certname])
      end

      nil
    end
  end

  action(:verify) do
    summary "Verify that the Puppet agent has a signed certificate"

    when_invoked do |opts|
      extend PuppetX::Puppetlabs::Bootstrap
      hostcert = Puppet::SSL::Certificate.indirection.find(Puppet[:certname])
      hostkey = Puppet::SSL::Key.indirection.find(Puppet[:certname])

      verify_signed_cert!(hostcert)
      verify_ssl_files_match!(hostcert, hostkey)
      verify_node_definition_reachable!

      hostcert
    end

    when_rendering :console do |cert|
      cert.content.to_s if cert
    end
  end
end
