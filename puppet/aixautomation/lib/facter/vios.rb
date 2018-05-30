# require_relative '../puppet_x/Automation/Lib/Log.rb'
# require_relative '../puppet_x/Automation/Lib/Constants.rb'
# require_relative '../puppet_x/Automation/Lib/Remote/c_rsh.rb'
#
# ##########################################################################
# name : vioss factor
# param : none
# return : hash of vioss
# description : this factor builds a fact called 'vioss' containing a hash
#  with all vioss names known by the NIM server as value.
#   oslevel -s as values.
# ##########################################################################
# include Automation::Lib
# include Automation::Lib::Remote
# this is not possible
# # Error: Facter: error while resolving custom facts in
# #  /etc/puppet/modules/aixautomation/lib/facter/vioss.rb:
# #  wrong argument type Class (expected Module)
# include Automation::Lib::Log
#
# Facter.add('vioss') do
#   setcode do
#
#     Log.log_info('Computing "vios" facter')
#
#     ##########################################################
#     #### Sample of use of log API
#     # Log.log_info("Sample info message")
#     # Log.log_debug("Sample debug message")
#     # Log.log_warning("Sample warning message")
#     # Log.log_err("Sample error message")
#     ####
#     ##########################################################
#
#     vioss = {}
#
#     vios_hash = {}
#     vioss_str = String.new
#     vioss_str = Facter::Core::Execution.execute("/usr/sbin/lsnim -t vios | /bin/awk \
# 'NR==FNR{print $1;next}{print $1}' | /bin/awk 'FNR!=1{print l}{l=$0};END{ORS=\"\";print l}' ORS=' '")
#     vioss_array = Array.new
#     vioss_array = vioss_str.split(' ')
#     vioss_array.each do |vios|
#       oslevel = ""
#       returned = Automation::Lib::Remote.c_rsh(vios, "/usr/bin/oslevel -s", oslevel)
#       if returned.success?
#         vios_hash['oslevel'] = oslevel.strip
#       end
#
#       #### ping
#       cmd = "/usr/sbin/ping -c1 -w5 #{vios}"
#       stdout, stderr, status = Open3.capture3("#{cmd}")
#       Log.log_debug("cmd   =#{cmd}")
#       Log.log_debug("status=#{status}")
#       if status.success?
#         Log.log_debug("stdout=#{stdout}")
#
#         ##### oslevel
#         oslevel = ""
#         returned = Automation::Lib::Remote.c_rsh(vios, "/usr/bin/oslevel -s", oslevel)
#         if returned.success?
#           vios_hash['oslevel'] = oslevel.strip
#
#           full_facter = true
#           if full_facter
#
#             ##### /etc/niminfo
#             niminfo_str = ""
#             returned = Automation::Lib::Remote.c_rsh(vios, "/bin/cat /etc/niminfo |\
#  /bin/grep '=' | /bin/sed 's/export //g'", niminfo_str)
#             if returned.success?
#               niminfo_lines = niminfo_str.split("\n")
#               niminfo_lines.each do |envvar|
#                 key, val = envvar.split('=')
#                 vios_hash[key] = val
#               end
#
#               ##### Cstate from lsnim -l
#               lsnim_str = Facter::Core::Execution.execute("/usr/sbin/lsnim -l " + vios)
#               lsnim_lines = lsnim_str.split("\n")
#               lsnim_lines.each do |lsnim_line|
#                 if lsnim_line =~ /^\s+Cstate\s+=\s+(.*)$/
#                   # Cstate
#                   cstate = Regexp.last_match(1)
#                   vios_hash['cstate'] = cstate
#
#                 elsif lsnim_line =~ /^\s+mgmt_profile1\s+=\s+(.*)$/
#                   # For VIOS store the management profile
#                   match_mgmtprof = Regexp.last_match(1)
#                   mgmt_elts = match_mgmtprof.split
#                   if mgmt_elts.size == 3
#                     vios_hash['mgmt_hmc_id'] = mgmt_elts[0]
#                     vios_hash['mgmt_vios_id'] = mgmt_elts[1]
#                     vios_hash['mgmt_cec_serial'] = mgmt_elts[2]
#                   end
#                 elsif lsnim_line =~ /^\s+if1\s+=\s+\S+\s+(\S+)\s+.*$/
#                   # IP
#                   vios_hash['vios_ip'] = Regexp.last_match(1)
#                 end
#               end
#
#               # yeah, we keep it !
#               vioss[vios] = vios_hash
#             else
#               Log.log_err("error while doing c_rsh '/bin/cat /etc/niminfo' on " + vios)
#               standalone_error = true
#             end
#           end
#         else
#           Log.log_err("error while doing c_rsh '/usr/bin/oslevel -s' on " + vios)
#           Log.log_err("stderr=#{stderr}")
#           standalone_error = true
#         end
#
#       else
#         Log.log_err("error while doing '/usr/sbin/ping -c1 -w5 ' " + vios)
#         Log.log_err("stderr=#{stderr}")
#         standalone_error = true
#       end
#
#     end
#
#     Log.log_info("vioss=" + vioss.to_s)
#     vioss
#   end
# end
#
