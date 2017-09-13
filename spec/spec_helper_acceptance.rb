require 'beaker-rspec/helpers/serverspec'
require 'beaker-rspec/spec_helper'
require 'beaker/puppet_install_helper'
require 'beaker/testmode_switcher/dsl'
require 'beaker/module_install_helper'

GEOTRUST_GLOBAL_CA = <<-EOM  
-----BEGIN CERTIFICATE-----
MIIDVDCCAjygAwIBAgIDAjRWMA0GCSqGSIb3DQEBBQUAMEIxCzAJBgNVBAYTAlVT  
MRYwFAYDVQQKEw1HZW9UcnVzdCBJbmMuMRswGQYDVQQDExJHZW9UcnVzdCBHbG9i  
YWwgQ0EwHhcNMDIwNTIxMDQwMDAwWhcNMjIwNTIxMDQwMDAwWjBCMQswCQYDVQQG  
EwJVUzEWMBQGA1UEChMNR2VvVHJ1c3QgSW5jLjEbMBkGA1UEAxMSR2VvVHJ1c3Qg  
R2xvYmFsIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2swYYzD9  
9BcjGlZ+W988bDjkcbd4kdS8odhM+KhDtgPpTSEHCIjaWC9mOSm9BXiLnTjoBbdq  
fnGk5sRgprDvgOSJKA+eJdbtg/OtppHHmMlCGDUUna2YRpIuT8rxh0PBFpVXLVDv  
iS2Aelet8u5fa9IAjbkU+BQVNdnARqN7csiRv8lVK83Qlz6cJmTM386DGXHKTubU  
1XupGc1V3sjs0l44U+VcT4wt/lAjNvxm5suOpDkZALeVAjmRCw7+OC7RHQWa9k0+  
bw8HHa8sHo9gOeL6NlMTOdReJivbPagUvTLrGAMoUgRx5aszPeE4uwc2hGKceeoW  
MPRfwCvocWvk+QIDAQABo1MwUTAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTA  
ephojYn7qwVkDBF9qn1luMrMTjAfBgNVHSMEGDAWgBTAephojYn7qwVkDBF9qn1l  
uMrMTjANBgkqhkiG9w0BAQUFAAOCAQEANeMpauUvXVSOKVCUn5kaFOSPeCpilKIn  
Z57QzxpeR+nBsqTP3UEaBU6bS+5Kb1VSsyShNwrrZHYqLizz/Tt1kL/6cdjHPTfS  
tQWVYrmm3ok9Nns4d0iXrKYgjy6myQzCsplFAMfOEVEiIuCl6rYVSAlk6l5PdPcF  
PseKUgzbFbS9bZvlxrFUaKnjaZC2mqUPuLk/IH2uSrW4nOQdtqvmlKXBx4Ot2/Un  
hw4EbNX/3aBd7YdStysVAq45pmp06drE57xNNB6pXE0zX5IJL4hmXXeXxx12E6nV  
5fEWCRE11azbJHFwLJhWC9kXtNHjUStedejV0NxPNO3CBWaAocvmMw==  
-----END CERTIFICATE-----
EOM



# automatically load any shared examples or contexts
Dir["./spec/support/**/*.rb"].sort.each { |f| require f }

run_puppet_install_helper
unless ENV['PUPPET_INSTALL_TYPE'] =~ /pe/i
  hosts.each do |host|
    create_remote_file(host, 'C:\Windows\Temp\geotrustglobal.pem', GEOTRUST_GLOBAL_CA)  
    on host, 'cmd /c certutil -v -addstore Root C:\Windows\Temp\geotrustglobal.pem'
  end 
end

# Install iis module either from source or from staging forge if given correct env variables
unless ENV['MODULE_provision'] == 'no'
  if ENV.has_key?('BEAKER_FORGE_HOST') && ENV.has_key?('BEAKER_FORGE_API')
    module_version = ENV.has_key?('MODULE_VERSION') || '>= 0.1.0'
    install_module_from_forge_on(hosts, 'puppetlabs-iis', module_version)
  else
    hosts.each do |host|
      install_module_on(host)
    end
  end
end

RSpec.configure do |c|
  # Configure all nodes in nodeset
  c.before :suite do
    unless ENV['BEAKER_TESTMODE'] == 'local' || ENV['BEAKER_provision'] == 'no'
      windows_hosts = hosts.select { |host| host.platform =~ /windows/i }
      install_module_from_forge_on(windows_hosts, 'puppetlabs/dism', '>= 1.2.0')
      # Install PS3 via Chocolatey
      install_module_from_forge_on(windows_hosts, 'puppetlabs/chocolatey', '>= 3.0.0')
      prereq_manifest = <<-EOS
        service {'wuauserv':
          enable  =>  'manual',
        }

        include chocolatey;

        dism { 'NetFx3': ensure => present }
 
        package {'powershell':
          ensure   => '4.0.20141001',
          provider => chocolatey,
        }
      EOS
      apply_manifest_on(windows_hosts, prereq_manifest)
      
      pp = "dism { ['IIS-WebServerRole','IIS-WebServer', 'IIS-WebServerManagementTools']: ensure => present }"
      apply_manifest_on(windows_hosts, pp)
    end
  end
end

def beaker_opts
  @env ||= {
    acceptable_exit_codes: (0...256),
    debug: true,
    trace: true,
  }
end
