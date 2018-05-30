require_relative '../puppet_x/Automation/Lib/Log.rb'
require_relative '../puppet_x/Automation/Lib/Constants.rb'
require_relative '../puppet_x/Automation/Lib/Remote/c_rsh.rb'

# ##########################################################################
# name : standalones factor
# param : none
# return : hash of standalones
# description : this factor builds a fact called 'standalones' containing a
#  hash with all standalones names known by the NIM server as value.
#   oslevel -s as values.
# ##########################################################################
include Automation::Lib
include Automation::Lib::Remote

Facter.add('standalones') do
  setcode do

    Log.log_info('Computing "standalones" facter')

    standalones = {}
    standalones_failure = {}

    standalones_str = Facter::Core::Execution.execute("/usr/sbin/lsnim -t standalone | \
/bin/awk 'NR==FNR{print $1;next}{print $1}' | \
/bin/awk 'FNR!=1{print l}{l=$0};END{ORS=\"\";print l}' ORS=' '")
    standalones_array = standalones_str.split(' ')

    #
    standalones_array.each do |standalone|
      standalone_hash = {}
      # To shorten execution, only keep some standalones
      # if standalone != "quimby01" && standalone != "quimby02"
      #  && standalone != "quimby03" \
      #  && standalone != "quimby04" && standalone != "quimby05" \
      #  && standalone != "quimby07" && standalone != "quimby08" \
      #  && standalone != "quimby09" && standalone != "quimby11"  \
      #  && standalone != "quimby12"
      #  Log.log_info("Please note, to shorten demo "+standalone+"
      #     standalone is not kept.")
      #  next
      # end

      # # To shorten execution, skip some standalones
      if standalone != 'quimby01' && standalone != 'quimby02' &&  standalone != 'quimby06'
        Log.log_info('Please note, to shorten demo ' + standalone +
                         ' standalone is not kept.')
        standalone_hash['standalone skipped reason']='Standalone system skipped in\
 aixautomation/lib/facter/standalones.rb'
        standalones_failure[standalone] = standalone_hash
        next
      end

      #### ping
      ping_cmd = '/usr/sbin/ping -c1 -w5 ' + standalone
      stdout, stderr, status = Open3.capture3(ping_cmd.to_s)
      Log.log_debug("ping_cmd=#{ping_cmd}")
      Log.log_debug("ping_status=#{status}")
      if status.success?
        Log.log_debug("ping_stdout=#{stdout}")
        ##### oslevel
        oslevel = ''
        oslevel_cmd = '/usr/bin/oslevel -s '
        returned = Automation::Lib::Remote.c_rsh(standalone,
                                                 oslevel_cmd,
                                                 oslevel)
        if returned.success?
          standalone_hash['oslevel'] = oslevel.strip

          full_facter = true
          if full_facter
            # #### /etc/niminfo
            niminfo_str = ''
            nim_cmd = "/bin/cat /etc/niminfo | /bin/grep '=' | /bin/sed 's/export //g'"
            returned = Automation::Lib::Remote.c_rsh(standalone,
                                                     nim_cmd,
                                                     niminfo_str)
            if returned.success?
              # Log.log_debug('niminfo_str=' + niminfo_str.to_s)
              niminfo_lines = niminfo_str.split("\n")
              # Log.log_debug('niminfo_lines=' + niminfo_lines.to_s)
              niminfo_lines.each do |envvar|
                key, val = envvar.split('=')
                standalone_hash[key] = val
                # Log.log_debug('standalone_hash[' + key + ']=' + val)
              end

              # #### Cstate from lsnim -l
              lsnim_str = Facter::Core::Execution.execute('/usr/sbin/lsnim -l ' +
                                                              standalone)
              lsnim_lines = lsnim_str.split("\n")
              keep_it = false
              lsnim_lines.each do |lsnim_line|
                # Cstate
                next unless lsnim_line =~ /^\s+Cstate\s+=\s+(.*)$/
                cstate = Regexp.last_match(1)
                standalone_hash['cstate'] = cstate
                # NEEDS TO BE TESTED AGAIN
                if cstate == 'ready for a NIM operation'
                  keep_it = true
                end
              end

              if keep_it

                # Get status of efix on this standalone
                remote_cmd = "/bin/lslpp -e | /bin/sed '/STATE codes/,$ d'"
                remote_output = []
                remote_cmd_status = Remote.c_rsh(standalone, remote_cmd, remote_output)
                if remote_cmd_status.success?
                  standalone_hash['lslpp -e'] = remote_output[0].chomp
                end

                # yeah, we keep it ! ping ok, lsnim ok, crsh ok, cstate ok
                standalones[standalone] = standalone_hash
                # Log.log_debug('standalones[' + standalone + ']=' + standalone_hash.to_s)
              else
                standalone_hash['ERROR']='Standalone '+standalone+' is not "ready for a NIM
operation"'
                Log.log_err('error on Cstate for : ' + standalone)
                standalones_failure[standalone] = standalone_hash
              end
            else
              standalone_hash['ERROR']='Standalone '+standalone+' does not "'+nim_cmd+'"'
              Log.log_err('error while doing "'+nim_cmd+'" on "' + standalone +'"')
              standalones_failure[standalone] = standalone_hash
            end
          else
            # yeah, we keep it ! ping ok, lsnim ok, crsh ok, cstate ok
            standalones[standalone] = standalone_hash
          end
        else
          standalone_hash['ERROR']='Standalone '+standalone+' does not "'+oslevel_cmd+'"'
          Log.log_err('error while doing "'+oslevel_cmd+'" on "' + standalone +'"')
          Log.log_err("stderr=#{stderr}")
          standalones_failure[standalone] = standalone_hash
        end
      else
        standalone_hash['ERROR']='Standalone '+standalone+' does not "'+ping_cmd+'"'
        Log.log_err('error while doing "'+ping_cmd+'"')
        Log.log_err("ping_stderr=#{stderr}")
        standalones_failure[standalone] = standalone_hash
      end
    end

    # Failure
    Log.log_err('standalones in failure="'+standalones_failure.to_s+'"')
    # persist to yaml
    failure_result_yml_file = 'standalones_in_failure.yml'
    File.write(failure_result_yml_file, standalones_failure.to_yaml)
    Log.log_debug('Refer to "'+failure_result_yml_file+'" to have results of standalones in failure.')

    # Success
    # persist to yaml
    result_yml_file = 'standalones.yml'
    File.write(result_yml_file, standalones.to_yaml)
    Log.log_debug('Refer to "'+result_yml_file+'" to have results of "standalones" facter.')
    standalones
  end
end
