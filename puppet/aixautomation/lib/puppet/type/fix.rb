require_relative '../../puppet_x/Automation/Lib/Utils.rb'
require_relative '../../puppet_x/Automation/Lib/Flrtvc.rb'

# ##########################################################################
# name : fix type
# description :
# ##########################################################################
Puppet::Type.newtype(:fix) do
  @doc = 'To manage all simple ifix functions.'
  feature :fix, 'The ability to manage simple ifix actions.', methods: [:fix]

  include Automation::Lib

  # ###########################################################################
  #
  # ###########################################################################
  ensurable do
    defaultvalues
    defaultto :present
  end

  # ###########################################################################
  #
  # ###########################################################################
  newparam(:name, :namevar => true) do
  end

  # ###########################################################################
  # Only valid targets are kept, targets nedd to be pingable,
  #  accessible thru c_rsh, in a proper NIM state
  # ###########################################################################
  newparam(:targets) do
    desc '"targets" parameter: list of lpar or vios on which to perform action'
    kept = []
    validate do |values|
      kept = []
      suppressed = []
      Utils.check_input_targets(values, kept, suppressed)
      raise('list of kept targets is empty, but cannot be empty') \
        if kept.empty?
    end
    munge do |_values|
      returned = Utils.string_separated(kept, ',')
      returned
    end
  end

  # ############################################################################
  #
  # ############################################################################
  newparam(:root) do
    desc '"root" parameter: download root directory for ifix'
    defaultto '/tmp'
    validate do |value|
      raise('"root" needs to exist') \
        if Utils.check_directory(value) == -1
    end
  end

  # ############################################################################
  #
  # ############################################################################
  newparam(:to_step) do
    desc '"to_step" parameter possible values: "installFlrtvc", runFlrtvc",
"parseFlrtvc", "downloadFixes", "checkFixes", "buildResource",
"installResource"'
    defaultto :installResource
    newvalues(:installFlrtvc, :runFlrtvc, :parseFlrtvc, :downloadFixes,
              :checkFixes, :buildResource, :installResource)
  end

  # ############################################################################
  #
  # ############################################################################
  newparam(:level) do
    desc '"level" parameter possible values: "hiper", "sec", "all"'
    defaultto :all
    newvalues(:hiper, :sec, :all)
  end

  # ############################################################################
  #
  # ############################################################################
  newparam(:clean) do
    desc '"clean" parameter possible values: "yes" or "no"'
    defaultto :yes
    newvalues(:yes, :no)
  end

  # ############################################################################
  #
  # ############################################################################
  validate do
    # NEEDS TO BE TESTED AGAIN
    # what is done here : if targets==null then failure
    raise('"targets" needs to be set') \
 if self[:targets].nil? || self[:targets].empty?

    # what is done here : if ensure==present and root==null then failure
    raise('"root" needs to be set if "ensure=>present"') \
      if self[:ensure] == 'present' && (self[:root].nil? || self[:root].empty?)

    # what is done here : if ensure=absent and clean==yes and root==null then failure
    raise('"root" needs to be set if "ensure=>absent" and "clean=>yes"') \
      if self[:ensure] == 'absent' && self[:clean] == 'yes' &&
        (self[:root].nil? || self[:root].empty?)
  end
end