resource_name :aix_tcpservice

property :identifier, String, name_property: true
property :immediate, [true, false], default: false

default_action :enable

action :enable do
  so = shell_out("egrep '^start /usr/(sbin|lib)/#{@new_resource.identifier}' /etc/rc.tcpip")
  enabled = so.exitstatus == 0

  immediate = '-S ' if @new_resource.immediate
  unless enabled
    converge_by('enable TCP/IP service') do
      shell_out("chrctcp #{immediate}-a #{@new_resource.identifier}")
    end
  end
end

action :disable do
  so = shell_out("egrep '^start /usr/(sbin|lib)/#{@new_resource.identifier}' /etc/rc.tcpip")
  enabled = so.exitstatus == 0

  immediate = '-S ' if @new_resource.immediate
  if enabled
    converge_by('disable TCP/IP service') do
      shell_out("chrctcp #{immediate}-d #{@new_resource.identifier}")
    end
  end
end

action :start do
  converge_by('start TCP/IP service') do
    shell_out("startsrc -s #{@new_resource.identifier}")
  end
end

action :stop do
  converge_by('stop TCP/IP service') do
    shell_out("stopsrc -s #{@new_resource.identifier}")
  end
end

action :restart do
  # refresh -s <subsystem> would be better, but not all subsystems support it
  action_stop
  # Sleep to give subsystem time to stop or else start will fail.
  sleep 2
  action_start
end

