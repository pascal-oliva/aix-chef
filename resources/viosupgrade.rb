#
# Copyright 2017, International Business Machines Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# TBC - uniformize use of log_xxx instead of Chef::Log.xxx in previous code
# TBC - uniformize use of put_xxx (pach_mgmt.rb) in previous code

include AIX::PatchMgmt

##############################
# PROPERTIES
##############################
property :desc, String, name_property: true
property :targets, String, required: true
property :ios_mksysb_name, String, required: true
property :viosupgrade_type, String, equal_to: %w(altdisk bosinst)
property :altdisks, String
property :installdisks, String
property :resources, String
property :common_resources, String
property :action_list, String, default: 'check,altdisk_copy,validate,upgrade' # no altdisk_cleanup by default
property :time_limit, String # mm/dd/YY HH:MM
property :disk_size_policy, String, default: 'nearest', equal_to: %w(minimize upper lower nearest)
property :preview, default: 'no', equal_to: %w(yes no)
property :viosupgrade_alt_disk_copy, default: 'no', equal_to: %w(yes no)
default_action :upgrade

##############################
# load_current_value
##############################
load_current_value do
end

##############################
# DEFINITIONS
##############################

class ViosHealthCheckError < StandardError
end

class ViosUpgradeConfFileError < StandardError
end

class ViosUpgradeError < StandardError
end

class ViosValUpgradeError < StandardError
end

class ViosUpgradeBadProperty < StandardError
end

class ViosResourceBadResource < StandardError
end

class ViosResourceBadLocation < StandardError
end

class ViosNoClusterFound < StandardError
end

# -----------------------------------------------------------------
# Check the vioshc script can be used
#
#    return 0 if success
#
#    raise ViosHealthCheckError in case of error
# -----------------------------------------------------------------
def check_vioshc
  vioshc_file = '/usr/sbin/vioshc.py'

  unless ::File.exist?(vioshc_file)
    msg = "Error: Health check script file '#{vioshc_file}': not found"
    raise ViosHealthCheckError, msg
  end

  unless ::File.executable?(vioshc_file)
    msg = "Error: Health check script file '#{vioshc_file}' not executable"
    raise ViosHealthCheckError, msg
  end

  0
end

# -----------------------------------------------------------------
# Check if viosupgrade file file can be used
#
#    return 0 if success
#
#    raise ViosUpgradeConfFileError in case of error
# -----------------------------------------------------------------
def check_viosupgrade_file(path_file)
  unless ::File.exist?(path_file)
    msg = "Error: viosupgrade config file '#{path_file}': not found"
    raise ViosUpgradeConfFileError, msg
  end
  0
end

# -----------------------------------------------------------------
# Check the specified resource location exists
#
#    return true if success
#
#    raise ViosUpgradeBadProperty in case of error
#    raise ViosResourceBadLocation in case of error
# -----------------------------------------------------------------
def check_resource_location(resource)
  location = ''
  ret = true

  # find location of resource
  cmd_s = "/usr/sbin/lsnim -a location #{resource}"
  log_info("check_source_location: '#{cmd_s}'")
  exit_status = Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stdout.each_line do |line|
      log_info("[STDOUT] #{line.chomp}")
      location = Regexp.last_match(1) if line =~ /.*location\s+=\s+(\S+)\s*/
    end
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    wait_thr.value # Process::Status object returned.
  end
  raise ViosUpgradeBadProperty, "Cannot find location of resource='#{resource}': Command '#{cmd_s}' returns above error." unless exit_status.success?

  # check to make sure path exists
  raise ViosResourceBadLocation, "Cannot find location='#{location}' of resource='#{resource}'" unless ::File.exist?(location)
  ret
end

# -----------------------------------------------------------------
# get the spot from resource
#
#    return spot name
#
#    raise ViosUpgradeBadProperty in case of error
#    raise ViosResourceBadResource in case of error
# -----------------------------------------------------------------
def get_spot_from_mksysb(resource)
  spot = ''

  # find spot of resource
  cmd_s = "/usr/sbin/lsnim -a extracted_spot #{resource}"
  log_info("get_spot_from_mksysb: '#{cmd_s}'")
  exit_status = Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stdout.each_line do |line|
      log_info("[STDOUT] #{line.chomp}")
      spot = Regexp.last_match(1) if line =~ /.*extracted_spot\s+=\s+(\S+)\s*/
    end
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    wait_thr.value # Process::Status object returned.
  end
  raise ViosUpgradeBadProperty, "Cannot find extracted_spot of resource='#{resource}': Command '#{cmd_s}' returns above error." unless exit_status.success?

  # check to make sure spot exists
  raise ViosResourceBadResource, "Cannot find extracted_spot='#{spot}' of resource='#{resource}'" if  shell_out("lsnim -l #{spot}").error?
  spot
end

# -----------------------------------------------------------------
# Collect VIOS and Managed System UUIDs.
#
#    This first call to the vioshc.py script intend to collect
#    UUIDs. The actual health assessment is performed in a second
#    call.
#
#    Return 0 if success
#
#    raise ViosHealthCheckError in case of error
# -----------------------------------------------------------------
def vios_health_init(nim_vios, hmc_id, hmc_ip)
  log_debug("vios_health_init: hmc_id='#{hmc_id}', hmc_ip='#{hmc_ip}'")
  ret = 0

  # first call to collect UUIDs
  cmd_s = "/usr/sbin/vioshc.py -i #{hmc_ip} -l a"
  log_info("Health Check: init command '#{cmd_s}'")

  Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stderr.each_line do |line|
      # nothing is print on stderr so far but log anyway
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    unless wait_thr.value.success?
      stdout.each_line { |line| log_info("[STDOUT] #{line.chomp}") }
      raise ViosHealthCheckError, "Heath check init command \"#{cmd_s}\" returns above error!"
    end

    data_start = 0
    vios_section = 0
    cec_uuid = ''
    cec_serial = ''

    # Parse the output and store the UUIDs
    stdout.each_line do |line|
      log_info("[STDOUT] #{line.chomp}")
      if line.include?('ERROR') || line.include?('WARN')
        # Needed this because vioshc.py script does not prints error to stderr
        put_warn("Heath check (vioshc.py) script: '#{line.strip}'")
        next
      end
      line.rstrip!

      if vios_section == 0
        # skip the header
        if line =~ /^-+\s+-+$/
          data_start = 1
          next
        end
        next if data_start == 0

        # New managed system section
        if line =~ /^(\S+)\s+(\S+)\s*$/
          unless cec_uuid == '' && cec_serial == ''
            put_warn("Health Check: unexpected script output: consecutive Managed System UUID: '#{line.strip}'")
          end
          cec_uuid = Regexp.last_match(1)
          cec_serial = Regexp.last_match(2)

          log_info("Health Check: init found managed system: cec_uuid:'#{cec_uuid}', cec_serial:'#{cec_serial}'")
          next
        end

        # New vios section
        if line =~ /^\s+-+\s+-+$/
          vios_section = 1
          next
        end

        # skip all header and empty lines until the vios section
        next
      end

      # new vios partition but skip if lparid is not found.
      next if line =~ /^\s+(\S+)\s+none$/

      # regular new vios partition
      if line =~ /^\s+(\S+)\s+(\S+)$/
        vios_uuid = Regexp.last_match(1)
        vios_part_id = Regexp.last_match(2)

        # retrieve the vios with the vios_part_id and the cec_serial value
        # and store the UUIDs in the dictionaries
        nim_vios.keys.each do |vios_key|
          next unless nim_vios[vios_key]['mgmt_vios_id'] == vios_part_id && nim_vios[vios_key]['mgmt_cec_serial'] == cec_serial

          nim_vios[vios_key]['vios_uuid'] = vios_uuid
          nim_vios[vios_key]['cec_uuid'] = cec_uuid
          log_info("Health Check: init found matching vios #{vios_key}: vios_part_id='#{vios_part_id}' vios_uuid='#{vios_uuid}'")
          break
        end
        next
      end

      # skip empty line after vios section. stop the vios section
      if line =~ /^\s*$/
        vios_section = 0
        cec_uuid = ''
        cec_serial = ''
        next
      end

      raise ViosHealthCheckError, "Health Check: init failed, bad script output for the #{hmc_id} hmc: '#{line}'"
    end
  end
  ret
end

# -----------------------------------------------------------------
# Health assessment of the VIOSes targets to ensure they can support
#    a rolling update operation.
#
#    This operation uses the vioshc.py script to evaluate the capacity
#    of the pair of the VIOSes to support the rolling update operation:
#
#    return: 0 if ok, 1 otherwise
# -----------------------------------------------------------------
def vios_health_check(nim_vios, hmc_ip, vios_list)
  log_debug("vios_health_check: hmc_ip: #{hmc_ip} vios_list: #{vios_list}")
  ret = 0
  rate = 0

  cmd_s = "/usr/sbin/vioshc.py -i #{hmc_ip} -m #{nim_vios[vios_list[0]]['cec_uuid']} "
  vios_list.each do |vios|
    cmd_s << "-U #{nim_vios[vios]['vios_uuid']} "
  end
  log_info("Health Check: init command '#{cmd_s}'")

  Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    ret = 1 unless wait_thr.value.success?

    # Parse the output to get the "Pass rate"
    stdout.each_line do |line|
      log_info("[STDOUT] #{line.chomp}")

      if line.include?('ERROR') || line.include?('WARN')
        # Need because vioshc.py script does not prints error to stderr
        put_warn("Heath check (vioshc.py) script: '#{line.strip}'")
      end
      next unless line =~ /Pass rate of/

      rate = Regexp.last_match(1).to_i if line =~ /Pass rate of (\d+)%/

      if ret == 0 && rate == 100
        put_info("VIOSes #{vios_list.join('-')} can be updated")
      else
        put_warn("VIOSes #{vios_list.join('-')} can NOT be updated: only #{rate}% of checks pass")
        ret = 1
      end
      break
    end
  end
  ret
end

# -----------------------------------------------------------------
# Build the viosupgrade command to run
#
#    return the command string to pass to run_viosupgrade()
#
# rubocop:disable Metrics/ParameterLists
# -----------------------------------------------------------------
def get_viosupgrade_cmd(nim_vios, vios, upgrade_type, ios_mksysb, installdisk, altdisk, resources, common_resources, preview, upg_altdisk)
  cmd = '/usr/sbin/viosupgrade '

  # type
  if !upgrade_type.nil? && !upgrade_type.empty?
    cmd << " -t #{upgrade_type}"
    log_info("[CMD] #{cmd}")
  end

  # mksysb and spot if necessary
  if !ios_mksysb.nil? && !ios_mksysb.empty? && check_resource_location(ios_mksysb)
    cmd << " -m #{ios_mksysb}"
    # get spot from mksysb
    if upgrade_type == 'bosinst'
      spot = get_spot_from_mksysb(ios_mksysb)
      cmd << " -p #{spot}"
      log_info("[CMD] #{cmd}")
    end
  end

  # altdisk for bosinst
  if !altdisk[vios].nil? && !altdisk[vios].empty? && upg_altdisk == 'yes' && upgrade_type == 'bosinst'
    cmd << " -r #{altdisk[vios]}"
    log_info("[CMD] #{cmd}")
  end

  # altdisk
  if !installdisk[vios].nil? && !installdisk[vios].empty?
    cmd << " -a #{installdisk[vios]}" if upgrade_type == 'altdisk'
    log_info("[CMD] #{cmd}")
  end

  # resources
  if !resources[vios].nil? && !resources[vios].empty?
    cmd << " -e #{resources[vios]}"
    if !common_resources.nil? && !common_resources.empty?
      cmd << ":#{common_resources}"
    end
  else
    cmd << " -e #{common_resources}" if !common_resources.nil? && !common_resources.empty?
  end
  log_info("[CMD] #{cmd}")

  # cluster
  cmd << ' -c' if nim_vios[vios]['ssp_vios_status'] == 'OK'

  # validation preview mode
  cmd << ' -v' if !preview.nil? && !preview.empty? && preview == 'yes'

  # skip clone from viosupgrade command
  cmd << ' -s' if upgrade_type == 'bosinst' && upg_altdisk == 'no'

  # add vios target
  cmd << " -n #{vios}"
  log_debug("get_viosupgrade_cmd - return cmd: '#{cmd}'")
  cmd
end

# -----------------------------------------------------------------
# Run vuisupgrade operation on specified vios
# The command to run is built by get_viosupgrade_cmd()
#
#    raise ViosUpgradeError in case of error
# -----------------------------------------------------------------
def run_viosupgrade(vios, cmd_s)
  put_info("Start upgrading vios '#{vios}' with viosupgrade.")
  log_info("run_viosupgrade: '#{cmd_s}'")
  if cmd_s.include?(' -v')
    put_info('validate operation.')
  else
    put_info("Starting viosupgrade operation for vios '#{vios}'.")
  end
  exit_status = Open3.popen3({ 'LANG' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stdout.each_line { |line| log_info("[STDOUT] #{line.chomp}") }
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    wait_thr.value # Process::Status object returned.
  end
  raise ViosUpgradeError, "Failed to perform viosupgrade operation on '#{vios}', see log file!" unless exit_status.success?
end

# -----------------------------------------------------------------
# get the spot from resource
#
#    return ssp id
#
#    raise ViosNoClusterFound if no cluster found
# -----------------------------------------------------------------
def get_ssp_name_id(nim_vios, vios)
  ssp_id = ''
  cmd_c = "/usr/lpp/bos.sysmgt/nim/methods/c_rsh #{nim_vios[vios]['vios_ip']} \"/etc/lsattr -El vioscluster0 \""
  log_info("get_ssp_name_id: '#{cmd_c}'")
  exit_status = Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_c) do |_stdin, stdout, stderr, wait_thr|
    stdout.each_line do |line|
      log_info("[STDOUT] #{line.chomp}")
      line.strip!
      ssp_id = Regexp.last_match(1) if line =~ /^cluster_id\s+(\S+).*/
    end
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    wait_thr.value # Process::Status object returned.
  end
  raise ViosNoClusterFound, "Cannot find cluster id for vios='#{nim_vios[vios]['vios_ip']}': Command '#{cmd_c}' returns above error." unless exit_status.success?
  ssp_id
end

# -----------------------------------------------------------------
# Check the SSP status of the VIOS tuple
# viosupgrade copy can be done when both VIOSes in the tuple
# refer to the same cluster and have the same SSP status = UP
# or if the vios is down
#
#    return  0 if OK
#            1 else
# rubocop:disable Style/GuardClause
# -----------------------------------------------------------------
def get_vios_ssp_status_for_upgrade(nim_vios, vios_list, vios_key, targets_status)
  ssp_name = ''
  vios_ssp_status = ''
  vios_name = ''
  err_label = 'FAILURE-SSP'

  vios_list.each do |vios|
    nim_vios[vios]['ssp_vios_status'] = 'none'
    nim_vios[vios]['ssp_name'] = 'none'
    nim_vios[vios]['ssp_id'] = 'none'
  end

  # get the SSP status
  vios_list.each do |vios|
    # vios = vios_list[0]

    # check if cluster defined
    begin
      nim_vios[vios]['ssp_id'] = get_ssp_name_id(nim_vios, vios)
      # cluster found
      log_info("[VIOS CLUSTER ID] #{nim_vios[vios]['ssp_id']}")
    rescue ViosNoClusterFound => e
      msg = "No cluster found: #{e.message} => continue to upgrade"
      log_info(msg)
      return 0 # no cluster found => continue to upgrade
    end

    # command for cluster status
    cmd_s = "/usr/lpp/bos.sysmgt/nim/methods/c_rsh #{nim_vios[vios]['vios_ip']} \"/usr/ios/cli/ioscli cluster -status -fmt :\""
    log_debug("ssp_status: '#{cmd_s}'")
    Open3.popen3({ 'LANG' => 'C', 'LC_ALL' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
      stderr.each_line do |line|
        STDERR.puts line
        log_info("[STDERR] #{line.chomp}")
      end
      unless wait_thr.value.success?
        stdout.each_line { |line| log_info("[STDOUT] #{line.chomp}") }
        msg = "Failed to get SSP status of #{vios_key}"
        log_warn("[#{vios}] #{msg}")
        raise ViosCmdError, "Error: #{msg} on #{vios}, command \"#{cmd_s}\" returns above error!"
      end

      # check that the VIOSes belong to the same cluster and have the same satus
      #                  or there is no SSP
      # stdout is like:
      # gdr_ssp3:OK:castor_gdr_vios3:8284-22A0221FD4BV:17:OK:OK
      # gdr_ssp3:OK:castor_gdr_vios2:8284-22A0221FD4BV:16:OK:OK
      #  or
      # Cluster does not exist.
      #
      stdout.each_line do |line|
        log_debug("[STDOUT] #{line.chomp}")
        line.chomp!
        if line =~ /^Cluster does not exist.$/
          log_debug("There is no cluster or the node #{vios} is DOWN")
          nim_vios[vios]['ssp_vios_status'] = 'DOWN'
          return 1 if vios_list.length == 1
          break
        end

        next unless line =~ /^(\S+):\S+:(\S+):\S+:\S+:(\S+):.*/
        cur_ssp_name = Regexp.last_match(1)
        cur_vios_name = Regexp.last_match(2)
        cur_vios_ssp_status = Regexp.last_match(3)

        next unless vios_list.include?(cur_vios_name)
        nim_vios[cur_vios_name]['ssp_vios_status'] = cur_vios_ssp_status
        nim_vios[cur_vios_name]['ssp_name'] = cur_ssp_name
        # single VIOS case
        if vios_list.length == 1
          # When single vios into the list => upgrade
          put_info('Single VIOS in the list is included into a cluster - stop upgrade')
          return 1
        end
        # first VIOS in the pair
        if ssp_name == ''
          ssp_name = cur_ssp_name
          vios_name = cur_vios_name
          vios_ssp_status = cur_vios_ssp_status
          next
        end

        # both VIOSes found
        if cur_vios_ssp_status == 'OK' && vios_ssp_status == cur_vios_ssp_status
          return 0
        elsif ssp_name != cur_ssp_name && cur_vios_ssp_status == 'OK'
          err_msg = "Both VIOSes: #{vios_key} does not belong to the same SSP. VIOSes cannot be updated"
          put_error(err_msg)
          targets_status[vios_key] = err_label
          return 1
        else
          return 1
        end
      end
    end
  end

  err_msg = 'SSP status undefined'
  put_error(err_msg)
  targets_status[vios_key] = err_label
  1
end

# -----------------------------------------------------------------
# Stop/start the SSP for a VIOS
#
#    ret = 0 if OK
#          1 else
# -----------------------------------------------------------------
def ssp_stop_start(vios_list, vios, nim_vios, action)
  # if action is start SSP,  find the first node running SSP
  node = vios
  if action == 'start'
    vios_list.each do |n|
      if nim_vios[n]['ssp_vios_status'] == 'OK'
        node = n
        break
      end
    end
  end
  cmd_s = "/usr/lpp/bos.sysmgt/nim/methods/c_rsh #{nim_vios[node]['vios_ip']} \"/usr/sbin/clctrl -#{action} -n #{nim_vios[vios]['ssp_name']} -m #{vios}\""

  log_debug("ssp_stop_start: '#{cmd_s}'")
  Open3.popen3({ 'LANG' => 'C' }, cmd_s) do |_stdin, stdout, stderr, wait_thr|
    stderr.each_line do |line|
      STDERR.puts line
      log_info("[STDERR] #{line.chomp}")
    end
    unless wait_thr.value.success?
      stdout.each_line { |line| log_info("[STDOUT] #{line.chomp}") }
      msg = "Failed to #{action} cluster #{nim_vios[vios]['ssp_name']} on vios #{vios}"
      log_warn(msg)
      raise ViosCmdError, "#{msg}, command: \"#{cmd_s}\" returns above error!"
    end
  end

  nim_vios[vios]['ssp_vios_status'] = if action == 'stop'
                                        'DOWN'
                                      else
                                        'OK'
                                      end
  log_info("#{action} cluster #{nim_vios[vios]['ssp_name']} on vios #{vios} succeed")

  0
end

##############################
# ACTION: upgrade
##############################
action :upgrade do
  # inputs
  log_info("VIOS UPGRADE - desc=\"#{new_resource.desc}\"")
  log_info("VIOS UPGRADE - action_list=\"#{new_resource.action_list}\"")
  log_info("VIOS UPGRADE - targets=#{new_resource.targets}")
  log_info("VIOS UPGRADE - targets=#{new_resource.viosupgrade_type}")
  STDOUT.puts ''
  STDERR.puts '' # TBC - needed for message presentation

  # check the action_list property
  allowed_action = %w(check altdisk_copy validate upgrade altdisk_cleanup)
  new_resource.action_list.delete(' ').split(',').each do |my_action|
    unless allowed_action.include?(my_action)
      raise ViosUpgradeBadProperty, "Invalid action '#{my_action}' in action_list '#{new_resource.action_list}', must be in: #{allowed_action.join(',')}"
    end
  end

  # check mandatory properties for the action_list
  if new_resource.action_list.include?('altdisk_copy') && (new_resource.altdisks.nil? || new_resource.altdisks.empty?)
    raise ViosUpgradeBadProperty, "Please specify an 'altdisks' property for altdisk_copy operation"
  end

  # check mandatory properties for the action_list
  if new_resource.viosupgrade_type == 'bosinst'
    if (new_resource.viosupgrade_alt_disk_copy == 'yes') && (new_resource.altdisks.nil? || new_resource.altdisks.empty?)
      raise ViosUpgradeBadProperty, "Please specify an 'altdisks' property for altdisk_copy operation "
    end
  end

  if new_resource.action_list.include?('upgrade')
    raise ViosUpgradeBadProperty, 'ios_mksysb_name is required for the upgrade operation' if new_resource.ios_mksysb_name.nil? || new_resource.ios_mksysb_name.empty?
  end

  # build time object from time_limit attribute,
  end_time = nil
  unless new_resource.time_limit.nil?
    if new_resource.time_limit =~ %r/^(\d{2})\/(\d{2})\/(\d{2,4}) (\d{1,2}):(\d{1,2})$/
      end_time = Time.local(Regexp.last_match(3).to_i,
                            Regexp.last_match(2).to_i,
                            Regexp.last_match(1).to_i,
                            Regexp.last_match(4).to_i,
                            Regexp.last_match(5).to_i)
      log_info("End time for operation: '#{end_time}'")
    else
      raise ViosUpgradeBadProperty, "Error: 'time_limit' property must be in the format: 'mm/dd/yy HH:MM', got:'#{new_resource.time_limit}'"
    end
  end

  log_info('Check NIM info is well configured')
  nim = Nim.new
  check_nim_info(node)

  # get hmc info
  log_info('Get NIM info for HMC')
  nim_hmc = nim.get_hmc_info()

  # get CEC list
  log_info('Get NIM info for Cecs')
  nim_cec = nim.get_cecs_info()

  # get the vios info
  log_info('Get NIM info for VIOSes')
  nim_vios = nim.get_nim_clients_info('vios')
  vio_server = VioServer.new

  # Complete the Cec serial in nim_vios dict
  nim_vios.keys.each do |key|
    nim_vios[key]['mgmt_cec_serial'] = nim_cec[nim_vios[key]['mgmt_cec']]['serial'] if nim_cec.keys.include?(nim_vios[key]['mgmt_cec'])
  end

  # build array of vios
  log_info("List of VIOS known in NIM: #{nim_vios.keys}")

  # build list of targets
  altdisk_hash = {}
  target_list = expand_vios_pair_targets(new_resource.targets, nim_vios.keys, new_resource.altdisks, altdisk_hash)

  # build installdisks
  installdisk_hash = build_installdisks(new_resource.targets, nim_vios.keys, new_resource.installdisks)

  # build resources
  resource_hash = build_resources(new_resource.targets, nim_vios.keys, new_resource.resources)

  # check vioshc script is executable
  check_vioshc if new_resource.action_list.include?('check')

  # main loop on target: can be 1-tuple or 2-tuple of VIOS
  targets_status = {}
  vios_key = ''
  target_list.each do |target_tuple|
    log_info("Working on target tuple: #{target_tuple}")

    vios_list = target_tuple.split(',')
    tup_len = vios_list.length
    vios1 = vios_list[0]
    if tup_len == 2
      vios2 = vios_list[1]
      vios_key = "#{vios1}-#{vios2}"
    else
      vios_key = vios1
      vios2 = nil
    end

    ###############
    # health_check
    if new_resource.action_list.include?('check')
      Chef::Log.info('VIOS UPGRADE - action=check')
      put_info("Health Check for VIOS tuple: #{target_tuple}")

      # Credentials
      log_info("Credentials (for VIOS: #{vios1})")
      hmc_id = nim_vios[vios1]['mgmt_hmc_id']

      unless nim_hmc.key?(hmc_id)
        # this should not happen
        put_error("Health Check, VIOS '#{vios1}' NIM management HMC ID '#{hmc_id}' not found")
        targets_status[vios_key] = 'FAILURE-HC'
        next # continue with next target tuple
      end
      hmc_ip = nim_hmc[hmc_id]['ip']

      # if needed call vios_health_init to get the UUIDs value
      if !nim_vios[vios1].key?('vios_uuid') || tup_len == 2 && !nim_vios[vios2].key?('vios_uuid')
        begin
          vios_health_init(nim_vios, hmc_id, hmc_ip)
        rescue ViosHealthCheckError => e
          targets_status[vios_key] = 'FAILURE-HC'
          put_error(e.message)
        end
        # Error case is handle by the next if statement
      end

      if tup_len == 1 && nim_vios[vios1].key?('vios_uuid') ||
         tup_len == 2 && nim_vios[vios1].key?('vios_uuid') && nim_vios[vios2].key?('vios_uuid')

        # run the vios_health check for the vios tuple
        ret = vios_health_check(nim_vios, hmc_ip, vios_list)

        targets_status[vios_key] = if ret == 0
                                     'SUCCESS-HC'
                                   else
                                     'FAILURE-HC'
                                   end
      else
        # vios uuid's not found
        if !nim_vios[vios1].key?('vios_uuid') && !nim_vios[vios2].key?('vios_uuid')
          vios_err = "#{vios1} and #{vios2}"
        elsif !nim_vios[vios1].key?('vios_uuid')
          vios_err = vios1 unless nim_vios[vios1].key?('vios_uuid')
        else
          vios_err = vios2 unless nim_vios[vios2].key?('vios_uuid')
        end
        targets_status[vios_key] = 'FAILURE-HC'
        msg = "Health Check did not get the UUID of VIOS: #{vios_err}"
        put_error(msg)
      end

      log_info("Health Check status for #{vios_key}: #{targets_status[vios_key]}")

      next if targets_status[vios_key] == 'FAILURE-HC' # continue with next target tuple

    end # check

    ###############
    # Alternate disk copy operation

    # check previous status and skip if failure
    if new_resource.action_list.include?('altdisk_copy') && new_resource.viosupgrade_alt_disk_copy == 'no'
      log_info('VIOS UPGRADE - action=altdisk_copy')
      log_info("VIOS UPGRADE - altdisks=#{new_resource.altdisks}")
      log_info("VIOS UPGRADE - disk_size_policy=#{new_resource.disk_size_policy}")
      log_info("Alternate disk copy for VIOS tuple: #{target_tuple}")

      # if health check status is known, check the vios tuple has passed
      if new_resource.action_list.include?('check') && targets_status[vios_key] != 'SUCCESS-HC'
        put_warn("Alternate disk copy for #{vios_key} VIOSes skipped (previous status: #{targets_status[vios_key]})")
        next
      end

      # check if there is time to handle this tuple
      if end_time.nil? || Time.now <= end_time
        # first find the right hdisk and check if we can perform the copy
        ret = 0

        rootvg_info = {}
        begin

          # check if the rootvg is mirrored
          vios_list.each do |vios|
            rootvg_info[vios] = vio_server.check_rootvg(nim_vios, vios)
          end

          ret = vio_server.find_valid_altdisk(nim_vios, vios_list, vios_key, rootvg_info, targets_status, altdisk_hash, new_resource.disk_size_policy)
          next if ret == 1
        rescue AltDiskFindError => e
          put_error(e.message)
          put_info("Finish NIM alt_disk_install operation for disk '#{altdisk_hash[vios_key]}' on vios '#{vios_key}': #{targets_status[vios_key]}.")
          next
        end

        # actually perform the alternate disk copy
        vios_list.each do |vios|
          error_label = if vios == vios1
                          'FAILURE-ALTDCOPY1'
                        else
                          'FAILURE-ALTDCOPY2'
                        end
          converge_by("\n nim: perform alt_disk_install for vios '#{vios}' on disk '#{altdisk_hash[vios]}'\n") do
            begin
              # unmirror the vg if necessary
              # check mirror
              nb_copies = rootvg_info[vios]['copy_dict'].keys.length
              put_info("rootvg_info = '#{rootvg_info}'\n")
              if nb_copies > 1
                begin
                  nim.perform_unmirror(nim_vios, vios, 'rootvg')
                rescue UnMirrorError => e
                  # ADD status
                  STDERR.puts e.message
                  log_warn("[#{vios}] #{e.message}")
                  targets_status[vios_key] = error_label
                  put_info("Finish NIM alt_disk_install operation using disk '#{altdisk_hash[vios]}' on vios '#{vios}': #{targets_status[vios_key]}.")
                  break
                end
              end

              put_info("Start NIM alt_disk_install operation using disk '#{altdisk_hash[vios]}' on vios '#{vios}'.")
              nim.perform_altdisk_install(vios, 'rootvg', altdisk_hash[vios])
            rescue NimAltDiskInstallError => e
              msg = "Failed to start the alternate disk copy on #{altdisk_hash[vios]} of #{vios}: #{e.message}"
              put_error(msg)
              targets_status[vios_key] = error_label
              put_info("Finish NIM alt_disk_install operation using disk '#{altdisk_hash[vios]}' on vios '#{vios}': #{targets_status[vios_key]}.")
              break
            end

            # wait the end of the alternate disk copy operation
            begin
              ret = nim.wait_alt_disk_install(vios)
            rescue NimLparInfoError => e
              STDERR.puts e.message
              log_warn("[#{vios}] #{e.message}")
              ret = 1
            end
            if ret == 0
              targets_status[vios_key] = 'SUCCESS-ALTDC'
              log_info("[#{vios}] VIOS altdisk copy succeeded on #{altdisk_hash[vios]}")
            else
              if ret == 1
                STDERR.puts e.message
                msg = "Alternate disk copy failed on #{altdisk_hash[vios]} of vios #{vios}"
                put_error(msg)
                ret = 1
              else
                msg = "Alternate disk copy failed on #{altdisk_hash[vios]}: timed out"
                put_warn(msg)
                STDERR.puts "#{msg} on vios #{vios}"
              end
              ret = 1

              targets_status[vios_key] = error_label
            end

            # mirror the vg if necessary
            nb_copies = rootvg_info[vios]['copy_dict'].keys.length
            if nb_copies > 1
              log_debug('mirror')
              begin
                nim.perform_mirror(nim_vios, vios, 'rootvg', rootvg_info)
              rescue MirrorError => e
                # ADD status
                STDERR.puts e.message
                log_warn("[#{vios}] #{e.message}")
                targets_status[vios_key] = error_label
                put_info("Finish NIM alt_disk_install operation using disk '#{altdisk_hash[vios]}' on vios '#{vios}': #{targets_status[vios_key]}.")
                break
              end
            end
            put_info("Finish NIM alt_disk_install operation for disk '#{altdisk_hash[vios]}' on vios '#{vios}': #{targets_status[vios_key]}.")
            break unless ret == 0
          end
        end
      else
        put_warn("Alternate disk copy for #{vios_key} skipped: time limit '#{new_resource.time_limit}' reached")
      end
      log_info("Alternate disk copy status for #{vios_key}: #{targets_status[vios_key]}")
    end # altdisk_copy

    ###############
    # validate
    if new_resource.action_list.include?('validate') || new_resource.preview == 'yes'
      Chef::Log.info('VIOS UPGRADE - action=validate')
      put_info("viosupgrade for VIOS tuple: #{target_tuple}")
      log_info("VIOS UPGRADE - type=#{new_resource.viosupgrade_type}")
      log_info("VIOS UPGRADE - mksysb resource=#{new_resource.ios_mksysb_name}")
      log_info("VIOS UPGRADE - preview=#{new_resource.preview}")

      # check SSP status of the tuple
      # Upgrade can only be done when Current Vios is UP and Vios Dual is UP
      # or if current vios is DOWN
      ret = 0
      begin
        ret = get_vios_ssp_status_for_upgrade(nim_vios, vios_list, vios_key, targets_status)
      rescue ViosCmdError => e
        put_error(e.message)
        targets_status[vios_key] = 'FAILURE-VALIDATE'
        log_info("Upgrade status for #{vios_key}: #{targets_status[vios_key]}")
        next # cannot continue - switch to next tuple
      end
      if ret == 1
        put_warn("Upgrade operation for #{vios_key} vioses skipped due to bad SSP status")
        put_info('Upgrade operation can be done if both of the VIOSes have the SSP status = UP')
        targets_status[vios_key] = 'FAILURE-VALIDATE'
        next # switch to next tuple
      end

      vios_list.each do |vios|
        targets_status[vios_key] = 'SUCCESS-VALIDATE'
        begin
          cmd_to_run = get_viosupgrade_cmd(nim_vios, vios, new_resource.viosupgrade_type,
            new_resource.ios_mksysb_name, installdisk_hash, altdisk_hash,
            resource_hash, new_resource.common_resources, 'yes', new_resource.viosupgrade_alt_disk_copy)
        rescue ViosUpgradeBadProperty, ViosResourceBadLocation => e
          put_error("Upgrade #{vios_key}: #{e.message}")
          targets_status[vios_key] = 'FAILURE-VALIDATE'
          log_info("Update status for #{vios_key}: #{targets_status[vios_key]}")
          break #
        end

        begin
          put_info("Start viosupgrade - validate operation - for vios '#{vios}'.")
          put_info("CMD= '#{cmd_to_run}'.")
          run_viosupgrade(vios, cmd_to_run)
        rescue ViosUpgradeError => e
          put_error(e.message)
          targets_status[vios_key] = 'FAILURE-VALIDATE'
          put_info("Finish viosupgrade validation for vios '#{vios}': #{targets_status[vios_key]}.")
          break #
        end
      end
      put_info("Validate status for #{vios_key}: #{targets_status[vios_key]}")
      next if targets_status[vios_key] == 'FAILURE-VALIDATE' # continue with next target tuple
    end # validate

    ########
    # upgrade
    if new_resource.action_list.include?('upgrade') && new_resource.preview == 'no'
      log_info('VIOS UPGRADE - action=upgrade')
      put_info("viosupgrade for VIOS tuple: #{target_tuple}")
      put_info("VIOS UPGRADE - type=#{new_resource.viosupgrade_type}")
      put_info("VIOS UPGRADE - mksysb resource=#{new_resource.ios_mksysb_name}")

      # check SSP status of the tuple
      # Upgrade can only be done when current VIOS is UP and VIOS Dual is UP
      # or if current vios is DOWN
      ret = 0
      begin
        ret = get_vios_ssp_status_for_upgrade(nim_vios, vios_list, vios_key, targets_status)
      rescue ViosCmdError => e
        put_error(e.message)
        targets_status[vios_key] = 'FAILURE-VALIDATE'
        log_info("Upgrade status for #{vios_key}: #{targets_status[vios_key]}")
        next # cannot continue - switch to next tuple
      end
      if ret == 1
        put_warn("Upgrade operation for #{vios_key} vioses skipped due to bad SSP status")
        put_info('Upgrade operation can be done if both of the VIOSes have the SSP status = UP')
        targets_status[vios_key] = 'FAILURE-VALIDATE'
        next # switch to next tuple
      end

      if new_resource.action_list.include?('validate') && targets_status[vios_key] != 'SUCCESS-VALIDATE'
        put_warn("Upgrade of #{vios_key} vioses skipped (previous status: #{targets_status[vios_key]})")
        next
      end

      # check if there is time to handle this tuple
      if end_time.nil? || Time.now <= end_time
        targets_status[vios_key] = 'SUCCESS-UPGRADE'
        vios_list.each do |vios|
          # check if altinst_rootvg exists else next tuple only for bosint
          if new_resource.viosupgrade_type == 'bosinst' && new_resource.viosupgrade_alt_disk_copy == 'no'
            ret = 0
            begin
              thash = {}
              ret = vio_server.get_altinst_rootvg_disk(nim_vios, vios, thash)
            rescue AltDiskFindError => e
              put_error(msg)
              ret = 1
            end
            if ret != 0
              targets_status[vios_key] = if vios == vios1
                                          'FAILURE-CHECK_ALT_DISK_VIOS1'
                                         else
                                           'FAILURE-CHECK_ALT_DISK_VIOS2'
                                         end
              put_warn("No No alternate disk found on '#{vios}'.")
              break # switch to next tuple
            end
          end

          # get upgrade command
          begin
            cmd_to_run = get_viosupgrade_cmd(nim_vios, vios,
              new_resource.viosupgrade_type, new_resource.ios_mksysb_name,
              installdisk_hash, altdisk_hash, resource_hash,
              new_resource.common_resources, 'no', new_resource.viosupgrade_alt_disk_copy)
          rescue ViosUpgradeBadProperty, VioslppSourceBadLocation => e
            put_error("Upgrade #{vios_key}: #{e.message}")
            targets_status[vios_key] = 'FAILURE-UPGRAD1'
            log_info("Upgrade status for #{vios_key}: #{targets_status[vios_key]}")
            break # switch to next tuple
          end

          break_required = false
          # set the error label
          err_label = if vios == vios1
                        'FAILURE-UPGRAD1'
                      else
                        'FAILURE-UPGRAD2'
                      end

          converge_by("\n nim: perform NIM viosupgrade for vios '#{vios}'\n") do
            begin
              put_info("Start viosupgrade for vios '#{vios}'.")
              run_viosupgrade(vios, cmd_to_run)
            rescue ViosUpgradeError => e
              put_error(e.message)
              targets_status[vios_key] = err_label
              put_info("Finish viosupgrade for vios '#{vios}': #{targets_status[vios_key]}.")
              # in case of failure
              break_required = true
            end
            # wait the end of viosupgrade operation
            begin
              ret = nim.wait_viosupgrade(nim_vios, vios)
            rescue ViosUpgradeQueryError => e
              STDERR.puts e.message
              log_warn("[#{vios}] #{e.message}")
              ret = 1
            end
            case ret
            when 0
              targets_status[vios_key] = 'SUCCESS-UPGRADE'
              put_info("[#{vios}] VIOS Upgrade succeeded")
            when -1
              msg = "VIOSUPGRADE failed on #{vios}: timed out"
              put_warn(msg)
              STDERR.puts msg
              targets_status[vios_key] = error_label
            else
              msg = "VIOSUPGRADE failed on #{vios}"
              put_warn(msg)
              STDERR.puts msg
              targets_status[vios_key] = error_label
            end
          end # end converge_by
          break if break_required
        end
      else
        put_warn("Upgrade #{vios_key} skipped: time limit '#{new_resource.time_limit}' reached")
      end
      put_info("Upgrade status for vios '#{vios_key}': #{targets_status[vios_key]}.")
    end # upgrade

    ###############
    # Alternate disk cleanup operation
    next unless new_resource.action_list.include?('altdisk_cleanup')
    log_info('VIOS UPGRADE - action=altdisk_cleanup')
    log_info("VIOS UPGRADE - altdisks=#{new_resource.altdisks}")
    log_info("Alternate disk cleanup for VIOS tuple: #{target_tuple}")

    # check previous status and skip if failure
    if new_resource.action_list.include?('upgrade') && targets_status[vios_key] != 'SUCCESS-UPGRADE' ||
       !new_resource.action_list.include?('upgrade') && new_resource.action_list.include?('altdisk_copy') && targets_status[vios_key] != 'SUCCESS-ALTDC' ||
       !new_resource.action_list.include?('upgrade') && !new_resource.action_list.include?('altdisk_copy') && new_resource.action_list.include?('check') && targets_status[vios_key] != 'SUCCESS-HC'
      put_warn("Alternate disk cleanup for #{vios_key} VIOSes skipped (previous status: #{targets_status[vios_key]}")
      next
    end

    # find the altinst_rootvg disk
    ret = 0
    vios_list.each do |vios|
      log_info("Alternate disk cleanup, get the alternate rootvg disk for vios #{vios}")
      begin
        ret = vio_server.get_altinst_rootvg_disk(nim_vios, vios, altdisk_hash)
      rescue AltDiskFindError => e
        msg = "Cleanup failed: #{e.message}"
        put_error(msg)
        ret = 1
        targets_status[vios_key] = if vios == vios1
                                     'FAILURE-ALTDCLEAN1'
                                   else
                                     'FAILURE-ALTDCLEAN2'
                                   end
      end
      put_warn("Failed to get the alternate disk on #{vios}") unless ret == 0
    end

    # perform the alternate disk cleanup
    vios_list.select { |k| altdisk_hash[k] != '' }.each do |vios|
      converge_by("vios: cleanup altinst_rootvg disk on vios '#{vios}'\n") do
        targets_status[vios_key] = if vios == vios1
                                     'FAILURE-ALTDCOPY1'
                                   else
                                     'FAILURE-ALTDCOPY2'
                                   end
        begin
          ret = vio_server.altdisk_copy_cleanup(nim_vios, vios, altdisk_hash)
        rescue AltDiskCleanError => e
          msg = "Cleanup failed: #{e.message}"
          put_error(msg)
        end
        if ret == 0
          targets_status[vios_key] = if vios == vios1
                                       'SUCCESS-ALTDCLEAN1'
                                     else
                                       'SUCCESS-ALTDCLEAN2'
                                     end
          log_info("Alternate disk cleanup succeeded on #{altdisk_hash[vios]} of #{vios}")
        else
          put_warn("Failed to clean the alternate disk on #{altdisk_hash[vios]} of #{vios}") unless ret == 0
        end
      end
    end

    log_info("Alternate disk cleanup status for #{vios_key}: #{targets_status[vios_key]}")
    # altdisk_cleanup
  end # target_list.each
  # Print target status
  put_info("Status synthesis for viosupgrade operation:\n")
  targets_status.each do |targ, v|
    put_info("Status  for :#{targ} => #{v}\n")
  end

end
