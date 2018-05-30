require_relative '../puppet_x/Automation/Lib/Log.rb'
require_relative '../puppet_x/Automation/Lib/Suma.rb'

# ##########################################################################
# name : servicepacks factor
# param : none
# return : hash of servicepacks per technical level
# description : this factor builds a fact called 'servicepacks' containing
#  a hash with all technical levels as keys and services packs as values.
# ##########################################################################
include Automation::Lib

Facter.add('servicepacks') do
  setcode do

    Log.log_info('Computing "servicepacks" facter')

    Log.log_debug('Suma.sp_per_tl')
    servicepacks = Suma.sp_per_tl
    Log.log_info('Service Packs per Technical Level =' + servicepacks.to_s)
    servicepacks
  end
end
