# == Class: haproxy
#
# A Puppet module, using storeconfigs, to model an haproxy configuration.
# Currently VERY limited - assumes Redhat/CentOS setup. Pull requests accepted!
#
# === Requirement/Dependencies:
#
# Currently requires the ripienaar/concat module on the Puppet Forge and
#  uses storeconfigs on the Puppet Master to export/collect resources
#  from all balancer members.
#
# === Parameters
#
# [*enable*]
#   Chooses whether haproxy should be installed or ensured absent.
#   Currently ONLY accepts valid boolean true/false values.
#
# [*global_options*]
#   A hash of all the haproxy global options. If you want to specify more
#    than one option (i.e. multiple timeout or stats options), pass those
#    options as an array and you will get a line for each of them in the
#    resultant haproxy.cfg file.
#
# [*defaults_options*]
#   A hash of all the haproxy defaults options. If you want to specify more
#    than one option (i.e. multiple timeout or stats options), pass those
#    options as an array and you will get a line for each of them in the
#    resultant haproxy.cfg file.
#
#
# === Examples
#
#  class { 'haproxy':
#    enable           => true,
#    global_options   => {
#      'log'     => "${::ipaddress} local0",
#      'chroot'  => '/var/lib/haproxy',
#      'pidfile' => '/var/run/haproxy.pid',
#      'maxconn' => '4000',
#      'user'    => 'haproxy',
#      'group'   => 'haproxy',
#      'daemon'  => '',
#      'stats'   => 'socket /var/lib/haproxy/stats'
#    },
#    defaults_options => {
#      'log'     => 'global',
#      'stats'   => 'enable',
#      'option'  => 'redispatch',
#      'retries' => '3',
#      'timeout' => [
#        'http-request 10s',
#        'queue 1m',
#        'connect 10s',
#        'client 1m',
#        'server 1m',
#        'check 10s'
#      ],
#      'maxconn' => '8000'
#    },
#  }
#
class haproxy (
  $manage_service       = true,
  $enable               = true,
  $global_options       = $haproxy::params::global_options,
  $defaults_options     = $haproxy::params::defaults_options,
  $nagios_contact_group = 'sysadmin-contact',
  $notification_period  = '24x7',
  $monitor              = hiera('monitor', true)
) inherits haproxy::params {
  include concat::setup

  package { 'haproxy':
    ensure  => $enable ? {
      true  => present,
      false => absent,
      default => absent
    },
    name    => 'haproxy',
  }

  if $enable {
    concat { '/etc/haproxy/haproxy.cfg':
      owner   => '0',
      group   => '0',
      mode    => '0644',
      require => Package['haproxy'],
      notify  => $manage_service ? {
        true   => Service['haproxy'],
        false  => undef,
        default => undef
      },
    }

    # Simple Header
    concat::fragment { '00-header':
      target  => '/etc/haproxy/haproxy.cfg',
      order   => '01',
      content => "# This file managed by Puppet\n",
    }

    # Template uses $global_options, $defaults_options
    concat::fragment { 'haproxy-base':
      target  => '/etc/haproxy/haproxy.cfg',
      order   => '10',
      content => template('haproxy/haproxy-base.cfg.erb'),
    }

    if ($::osfamily == 'Debian') {
      file { '/etc/default/haproxy':
        content => 'ENABLED=1',
        require => Package['haproxy'],
        before  => $manage_service ? {
          true    => Service['haproxy'],
          false   => undef,
          default => undef
        },
      }
    }

    file { $global_options['chroot']:
      ensure => directory,
    }

  }

  if $manage_service {
    service { 'haproxy':
      ensure     => $enable ? {
        true    => running,
        false   => stopped,
        default => stopped
      },
      enable     => $enable ? {
        true    => true,
        false   => false,
        default => false
      },
      name       => 'haproxy',
      hasrestart => true,
      hasstatus  => true,
      require    => [
        Concat['/etc/haproxy/haproxy.cfg'],
        File[$global_options['chroot']],
      ],
    }
  }
  
  if ($monitor == true) {

    include nagios::target::params
  
    # Add nrpe check for running tomcat instance
    concat::fragment { "check_haproxy_${::fqdn}":
      target  => "/etc/nrpe.d/10-${::hostname}-checks.cfg",
      content => inline_template("command[check_haproxy_${::fqdn}]=${nagios::target::params::nagios_plugin_dir}/check_procs -c 1:1 -u haproxy -C haproxy -a haproxy\n"),
    }  
    
    
    # Add exported nagios_service to monitor that tomcat is running
    @@nagios_service { "check_haproxy_${::fqdn}":
      check_command       => "check_nrpe!check_haproxy_${::fqdn}",
      use                 => 'generic-service',
      host_name           => $::fqdn,
      contact_groups      => $nagios_contact_group,
      notification_period => $notification_period,
      service_description => 'HA-Proxy Running',
      icon_image          => 'proxy_server.png',
      icon_image_alt      => 'haproxy',
    }    
  
  }
}
