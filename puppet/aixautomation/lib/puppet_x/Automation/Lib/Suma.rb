require_relative './SpLevel.rb'
require_relative './Constants.rb'
require_relative './Utils.rb'
require 'yaml'

module Automation
  module Lib
    # #########################################################################
    # Class Suma
    # #########################################################################
    #  Suma class implementation with methods to
    #   1) query metadata
    #    Suma metadata are queried and analysed to that of available list of SP
    #    per TL is generated.
    #    Results of Suma metadata queries is stored into yml file so that this
    #     done only once.
    #     This is used to check parameters
    #   2) preview data
    #    If preview shows something needs to be downloaded, then download is
    #     triggered
    #   3) download data
    #    Into root directory + naming conventions
    #     <root>/<type>/<from>/<to>/installp/ppc/...
    #
    # Metadata requests generated
    #  /usr/sbin/suma -x -a "DisplayName="Downloading '7100-03' metadata"
    #   -a FilterML=7100-03 -a DLTarget=/tmp/suma/metadata/7100-03
    #   -a FilterDir=/tmp/suma/metadata/7100-03
    #   -a RqType=Latest
    #   -a Action=Metadata
    #  /usr/sbin/suma -x -a "DisplayName=Downloading '7100-03' metadata"
    #   -a FilterML=7100-03 -a DLTarget=/tmp/suma/metadata/7100-03
    #   -a FilterDir=/tmp/suma/metadata/7100-03
    #   -a RqType=SP -a RqName=7100-03-05-1524
    #   -a Action=Metadata
    # ########################################################################
    class Suma
      attr_accessor :dir_metadata
      attr_accessor :dir_lpp_sources
      attr_accessor :lpp_source
      attr_accessor :to_step

      # ######################################################################
      # name : initialize
      # param :input:args:arrays of strings
      #     args[0]:string  root download directory, will contain
      #       metadata and lpp_sources sub-directories
      #     args[1]:clean:string to clean everything and restart downloads
      #       from scratch
      #     args[2]:from_level:string   for example "7100-01"
      #     args[3]:to_level:string for example "7100-03-05-1524"",
      #       can be empty
      #     args[4]:type:string :TL :SP :Latest
      #     args[5]:lpp_source:string lpp_source to be built with suma downloads
      # return :
      # description : instantiate Suma request, either metadata, or
      #   download or download-preview request.
      # ######################################################################
      def initialize(args)
        if args.size < 6
          raise('Suma constructor needs at least 7 parameters in its "args" \
parameter. Cannot continue!')
        end
        #
        root = args[0]
        clean = args[1]
        from_level = args[2]
        to_level = args[3]
        type = args[4]
        to_step = args[5]
        lpp_source = args[6]
        # /^\// ok
        # %r{^\/} ok
        @root_dir = if root =~ %r{^\/}
                      root
                    else
                      ::File.join(Dir.pwd,
                                  root)
                    end
        @to_step = to_step.to_s
        @dir_metadata = ::File.join(@root_dir,
                                    'metadata',
                                    from_level)
        # Check metadata root directory
        Utils.check_directory(@dir_metadata)
        Log.log_debug('dir_metadata=' + @dir_metadata)
        #
        filter_ml = ' -a FilterML=' + from_level
        rq_type = ' -a RqType=' + type.to_s
        rq_name = ' '
        #
        @display_metadata = ' -a DisplayName="Downloading metadata into ' + @dir_metadata.to_s + '"'
        if to_level != ''
          rq_name = ' -a RqName=' + to_level
          @dir_lpp_sources = ::File.join(@root_dir,
                                         'lpp_sources',
                                         type.to_s,
                                         from_level,
                                         to_level)
          @display_lpp_sources = ' -a DisplayName="Downloading lppsources into ' + @dir_lpp_sources.to_s + '"'
          @lpp_source = if lpp_source.nil? || lpp_source.empty?
                          'PAA_' + type.to_s + '_' + from_level + '_' + to_level
                        else
                          lpp_source
                        end
        else
          @dir_lpp_sources = ::File.join(@root_dir,
                                         'lpp_sources',
                                         type.to_s,
                                         from_level)
          @display_lpp_sources = ' -a DisplayName="Downloading lppsources into ' + @dir_lpp_sources.to_s + '"'
          @lpp_source = if lpp_source.nil? || lpp_source.empty?
                          'PAA_' + type.to_s + '_' + from_level
                        else
                          lpp_source
                        end
        end
        # Check lpp_sources root directory
        Utils.check_directory(@dir_lpp_sources)
        Log.log_debug('dir_lpp_source=' + @dir_lpp_sources)
        #
        @dl = 0.0
        @downloaded = 0
        @failed = 0
        @skipped = 0
        @suma_command = '/usr/sbin/suma -x ' + rq_type + rq_name + filter_ml
      end

      # #######################################################################
      # name : metadata
      # param : none
      # return :
      # description :
      # #######################################################################
      def metadata
        returned = true
        dl_target = ' -a DLTarget=' + @dir_metadata
        filter_dir = ' -a FilterDir=' + @dir_metadata
        action = ' -a Action=Metadata'
        metadata_suma_command = @suma_command + @display_metadata + action +
            dl_target + filter_dir
        Log.log_info('SUMA metadata operation: ' + metadata_suma_command)
        #
        begin
          stdout, stderr, exit_status = Open3.capture3({ 'LANG' => 'C' },
                                                       metadata_suma_command)
          unless exit_status.nil?
            Log.log_info('exit_status=' + exit_status.to_s)
          end
          #
          stdout.each_line do |line|
            Log.log_debug(line.chomp.to_s)
          end
          stderr.each_line do |line|
            # To improve : we might have to distinguish between these errors
            returned = false if line =~ /0500-035 No fixes match your query./
            returned = false if line =~ /0500-059 Entitlement is required to download./
            returned = false if line =~ /0500-012 An error occurred attempting to download./
            Log.log_err(line.chomp.to_s)
          end
        rescue StandardError => e
          Log.log_err('e=' + e.to_s) unless e.nil?
          returned = false
          unless exit_status.success?
            raise SumaMetadataError,
                  'Error: Command ' + metadata_suma_command + ' returns above error!'
          end
        end
        Log.log_info('Done data metadata operation: ' + metadata_suma_command)
        returned
      end

      # ########################################################################
      # name : preview
      # param : none
      # return :
      # description :
      # ########################################################################
      def preview
        dl_target = ' -a DLTarget=' + @dir_lpp_sources
        filter_dir = ' -a FilterDir=' + @dir_lpp_sources
        action = ' -a Action=Preview'
        preview_suma_command = @suma_command + @display_lpp_sources +
            action + dl_target + filter_dir
        Log.log_info('SUMA preview operation: ' + preview_suma_command)
        preview_error = false
        missing = false
        #
        exit_status = Open3.popen3({ 'LANG' => 'C' }, preview_suma_command) \
do |_stdin, stdout, stderr, wait_thr|
          unless exit_status.nil?
            Log.log_info('exit_status=' + exit_status.to_s)
          end
          #
          stdout.each_line do |line|
            @dl = Regexp.last_match(1).to_f / 1024 / 1024 / 1024 \
if line =~ /Total bytes of updates downloaded: ([0-9]+)/
            @downloaded = Regexp.last_match(1).to_i \
if line =~ /([0-9]+) downloaded/
            @failed = Regexp.last_match(1).to_i if line =~ /([0-9]+) failed/
            @skipped = Regexp.last_match(1).to_i if line =~ /([0-9]+) skipped/
            Log.log_info(line.chomp.to_s)
          end
          #
          Log.log_info('@dl=' + @dl.to_s +
                           ' @downloaded=' + @downloaded.to_s +
                           ' @failed=' + @failed.to_s +
                           ' @skipped=' + @skipped.to_s)
          stderr.each_line do |line|
            preview_error = true if line =~ /0500-035 No fixes match your query./
            Log.log_err(line.chomp.to_s)
          end
          wait_thr.value # Process::Status object returned.
          @preview_done = true
        end
        #
        if preview_error
          raise SumaPreviewError,
                'Error: Command ' + preview_suma_command + ' returns above error!'
        end
        #
        missing = true if @downloaded != 0 || @dl != 0.0
        #
        unless preview_error
          Log.log_warning('Preview: ' +
                              @downloaded.to_s +
                              ' downloaded (' + @dl.round(2).to_s + ' GB), ' +
                              @failed.to_s +
                              ' failed, ' +
                              @skipped.to_s +
                              ' skipped fixes')
        end
        #
        Log.log_info('Done data preview operation: ' +
                         preview_suma_command +
                         ' missing:' +
                         missing.to_s)
        missing
      end

      # #######################################################################
      # name : download
      # param : none
      # return :
      # description :
      # #######################################################################
      def download
        dl_target = ' -a DLTarget=' + @dir_lpp_sources
        filter_dir = ' -a FilterDir=' + @dir_lpp_sources
        action = ' -a Action=Download'
        download_suma_command = @suma_command + @display_lpp_sources +
            action + dl_target + filter_dir
        Log.log_info('SUMA download operation: ' + download_suma_command)
        #
        succeeded = 0
        failed = 0
        skipped = 0
        download_dl = 0
        download_downloaded = 0
        download_failed = 0
        download_skipped = 0
        if @preview_done
          Log.log_info('Start downloading ' + @downloaded.to_s +
                           ' fixes (~ ' + @dl.round(2).to_s + ' GB).')
          @preview_done = false
        else
          Log.log_info('Start downloading fixes.')
        end
        #
        exit_status = Open3.popen3({ 'LANG' => 'C' }, download_suma_command) \
do |_stdin, stdout, stderr, wait_thr|
          thr = Thread.new do
            start = Time.now
            loop do
              Log.log_info("\033[2K\rSUCCEEDED: \
                           #{succeeded}/#{@downloaded}\tFAILED: #{failed}/#{@failed}\
                           \tSKIPPED: #{skipped}/#{@skipped}. \
(Total time: #{duration(Time.now - start)}).")
              sleep 1
            end
          end
          #
          stdout.each_line do |line|
            succeeded += 1 if line =~ /^Download SUCCEEDED:/
            failed += 1 if line =~ /^Download FAILED:/
            skipped += 1 if line =~ /^Download SKIPPED:/
            download_dl = Regexp.last_match(1).to_f / 1024 / 1024 / 1024 \
if line =~ /Total bytes of updates downloaded: ([0-9]+)/
            download_downloaded = Regexp.last_match(1).to_i \
if line =~ /([0-9]+) downloaded/
            download_failed = Regexp.last_match(1).to_i \
if line =~ /([0-9]+) failed/
            download_skipped = Regexp.last_match(1).to_i \
if line =~ /([0-9]+) skipped/
            Log.log_debug(line.chomp.to_s)
          end
          #
          stderr.each_line do |line|
            Log.log_err(line.chomp.to_s)
          end
          thr.exit
          wait_thr.value # Process::Status object returned.
        end
        #
        Log.log_info("Finish downloading #{succeeded} \
fixes (~ #{download_dl.to_f.round(2)} GB).")
        Log.log_info('Done data download operation ' +
                         download_suma_command)
        unless exit_status.success?
          raise SumaDownloadError,
                'Error: Command ' + download_suma_command +
                    ' returns above error!'
        end
        @dl = download_dl
        @downloaded = download_downloaded
        @failed = download_failed
        @skipped = download_skipped
      end

      # #####################################################################
      # name : sp_per_tl
      # return : hash containing list of servicepacks per technical level
      # description : generate as many data metadata requests than necessary
      #  to be able to build hash containing all results. Store results into
      #  a yaml file. If yaml file already exists, then return contents
      #  of file instead.
      # #####################################################################
      def self.sp_per_tl
        Log.log_debug('Suma.sp_per_tl')
        #
        # If yaml file exists, return its contents
        # otherwise mine metadata to build results
        #
        root_directory = ::File.join(Constants.output_dir,
                                     'facter')
        metadata_root_directory = ::File.join(root_directory,
                                              'suma')
        yml_file = ::File.join(root_directory,
                               'sp_per_tl.yml')
        mine_metadata = false
        begin
          Log.log_info('Attempting to load ' + yml_file + ' file')
          sp_per_tl_from_file = YAML.load_file(yml_file)
          if sp_per_tl_from_file.nil?
            Log.log_info('Service Packs per Technical Level not found into ' +
                             yml_file)
            mine_metadata = true
          elsif sp_per_tl_from_file.empty?
            Log.log_info('Service Packs per Technical Level not set into ' +
                             yml_file)
            mine_metadata = true
          else
            Log.log_info('Service Packs per Technical Level found into ' +
                             yml_file)
          end
        rescue StandardError
          Log.log_warning('Service Packs per Technical Level ' + yml_file + ' not found ' +
                              ' : compute it by downloading Suma Metadata')
          mine_metadata = true
        end
        #
        # yaml does not exist yet, build it
        #
        if mine_metadata
          hr_versions = %w(6.1 7.1 7.2)
          sp_per_tl = {}
          #
          hr_versions.each do |hr_version|
            #
            metadata_index = 0
            metadata_successive_failures = 0
            metadata_tl_failures = []
            max_failure = 3
            while metadata_successive_failures < max_failure
              begin
                technical_levels = SpLevel.technical_level(hr_version, metadata_index)
                technical_level = technical_levels[:technical_level]
                sps_of_tl = []
                #
                # Retrieve the data
                suma = Suma.new([metadata_root_directory, :no, technical_level, '', 'Latest', :download, ''])
                #
                metadata_return_code = suma.metadata
                if metadata_return_code
                  dirmeta = ::File.join(metadata_root_directory,
                                        'metadata',
                                        technical_level,
                                        'installp',
                                        'ppc')
                  list_of_files =
                      Dir.glob(::File.join(dirmeta,
                                           technical_level + '*.xml'))
                  list_of_files.collect! do |file|
                    ::File.open(file) do |f|
                      servicepack = nil
                      s = f.read
                      # ### BUG SUMA WORKAROUND ###
                      s = s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
                      # ######### END #############
                      servicepack = Regexp.last_match(1) \
if s.to_s =~ /^<SP name="([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4})">/
                      unless servicepack.nil?
                        sps_of_tl.push(servicepack)
                      end
                    end
                  end
                  sp_per_tl[technical_level] = sps_of_tl
                  metadata_successive_failures = 0
                  metadata_tl_failures = []
                else
                  sp_per_tl[technical_level] = []
                  metadata_successive_failures += 1
                  metadata_tl_failures.push(technical_level)
                end
              end
              metadata_index += 1
            end
            #
            next unless metadata_successive_failures >= max_failure
            index = 0
            begin
              to_remove = metadata_tl_failures.pop
              sp_per_tl.delete(to_remove)
              index += 1
            end while index < max_failure
          end
          #
          # Everything should be cleaned at the end
          #
          FileUtils.rm_rf(metadata_root_directory)
          Log.log_debug('Created Service Packs per Technical Level =' +
                            sp_per_tl.to_s)
          # persist to yaml
          File.write(yml_file, sp_per_tl.to_yaml)
          sp_per_tl
        else
          #
          # Everything should be cleaned at the end
          #
          FileUtils.rm_rf(metadata_root_directory)
          sp_per_tl_from_file
        end
      end

      # #######################################################################
      # name : column_presentation
      # param :input:data:string
      # return : column format presentation of a dictionary
      # description : present dictionary in column format
      #    +---------+-----------------+---------------------------+
      #    | machine |     oslevel     |          Cstate           |
      #    +---------+-----------------+---------------------------+
      #    | client1 | 7100-01-04-1216 | ready for a NIM operation |
      #    | client2 | 7100-03-01-1341 | ready for a NIM operation |
      #    | client3 | 7100-04-00-0000 | ready for a NIM operation |
      #    | master  | 7200-01-00-0000 |                           |
      #    +---------+-----------------+---------------------------+
      # #######################################################################
      def self.column_presentation(data)
        widths = {}
        data.keys.each do |key|
          widths[key] = 5 # minimum column width
          # longest string len of values
          val_len = data[key].max_by { |v| v.to_s.length }.to_s.length
          widths[key] = val_len > widths[key] ? val_len : widths[key]
          # length of key
          widths[key] = key.to_s.length > widths[key] ? key.to_s.length : widths[key]
        end

        result = ' + '
        data.keys.each { |key| result += ''.center(widths[key] + 2, '-') + ' + ' }
        result += '\n'
        result += '|'
        data.keys.each { |key| result += key.to_s.center(widths[key] + 2) + '|' }
        result += '\n'
        result += ' + '
        data.keys.each { |key| result += ''.center(widths[key] + 2, '-') + ' + ' }
        result += '\n'
        length = data.values.max_by(&:length).length
        0.upto(length - 1).each do |i|
          result += '|'
          data.keys.each { |key| result += data[key][i].to_s.center(widths[key] + 2) + '|' }
          result += '\n'
        end
        result += ' + '
        data.keys.each { |key| result += ''.center(widths[key] + 2, '-') + ' + ' }
        result += '\n'
        result
      end
    end # Suma

    # ############################
    #     E X C E P T I O N      #
    # ############################
    class SumaError < StandardError
    end
    #
    class SumaMetadataError < SumaError
    end
    #
    class SumaPreviewError < SumaError
    end
    #
    class SumaDownloadError < SumaError
    end
    #
  end
end
