#!/usr/bin/env ruby
# vimball.rb
# @Author:      Tom Link (micathom AT gmail com)
# @License:     GPL (see http://www.gnu.org/licenses/gpl.txt)
# @Created:     2009-02-10.
# @Last Change: 2010-11-06.
#
# This script creates and installs vimballs without vim.
#
# Before actually using this script, you might want to run
#
#   vimball.rb --print-config
#
# and check the values. If they don't seem right, you can change them in 
# the configuration file (in YAML format).
#
# Known incompatibilities:
# - Vim's vimball silently converts windows line end markers to unix 
# markers. This script won't -- unless you run it with Windows's ruby 
# maybe.


require 'yaml'
require 'logger'
require 'optparse'
require 'pathname'
require 'fileutils'
require 'zlib'
require 'rbconfig'
require 'yaml'
require 'digest/md5'


class Vimball

    APPNAME = 'vimball'
    VERSION = '1.0.217'
    HEADER = <<HEADER
" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.
UseVimball
finish
HEADER


    class AppLog
        def initialize(output=$stdout)
            @output = output
            $logger = Logger.new(output)
            $logger.progname = APPNAME
            $logger.datetime_format = "%H:%M:%S"
            AppLog.set_level
        end
    
        def self.set_level
            if $DEBUG
                $logger.level = Logger::DEBUG
            elsif $VERBOSE
                $logger.level = Logger::INFO
            else
                $logger.level = Logger::WARN
            end
        end
    end


    class << self

        def with_args(args)

            AppLog.new

            config = Hash.new

            config['vimfiles'] = catch(:ok) do
                throw :ok, ENV['VIMFILES'] if ENV['VIMFILES']
                ['.vim', 'vimfiles'].each do |dir|
                    ['HOME', 'USERPROFILE', 'VIM'].each do |env|
                        pdir = ENV[env]
                        if pdir
                            vimfiles = File.join(pdir, dir)
                            throw :ok, vimfiles if File.directory?(vimfiles)
                        end
                    end
                end
                $logger.warn "Couldn't find your vimfiles directory."
                $logger.warn "Please use the -b command-line option,"
                $logger.warn "or set it in your config file."
                '.'
            end
            config['installdir'] = config['vimfiles']

            config['configfile'] = File.join(config['vimfiles'], 'vimballs', "config_#{ENV['HOSTNAME']}.yml")
            unless File.exists?(config['configfile'])
                config['configfile'] = File.join(config['vimfiles'], 'vimballs', 'config.yml')
            end
            @configs = []
            read_config(config)

            config['compress'] ||= false
            config['helptags'] ||= %{vim -T dumb -c "helptags %s" -cq"}
            config['outdir']   ||= File.join(config['vimfiles'], 'vimballs')
            config['vimoutdir'] ||= nil
            config['dry']      ||= false
            config['record']   ||= true
            config['repo']     ||= false
            config['repodir']  ||= 'bundle'

            opts = OptionParser.new do |opts|
                opts.banner =  'Usage: vimball.rb [OPTIONS] COMMAND ARGS ...'
                opts.separator ' '
                opts.separator 'vimball.rb is a free software with ABSOLUTELY NO WARRANTY under'
                opts.separator 'the terms of the GNU General Public License version 2 or newer.'
                opts.separator ' '
                opts.separator 'Commands:'
                opts.separator '   install VIMBALL ... Install a vimball (implicit if the only argument ends with ".vba")'
                opts.separator '   vba RECIPE      ... Create a vimball'
                opts.separator '   list VIMBALL    ... List files in a vimball'
                opts.separator ' '

                opts.on('-b', '--vimfiles DIR', String, 'Vimfiles directory') do |value|
                    config['vimfiles'] = value
                end

                opts.on('-c', '--config YAML', String, 'Config file') do |value|
                    config['configfile'] = value
                    read_config(config)
                end

                opts.on('-d', '--dir DIR', String, 'Destination directory for vimballs') do |value|
                    config['outdir'] = value
                end

                opts.on('-D', '--dir4vim DIR', String, 'Destination directory name for vim (don\'t use this unless you\'re me)') do |value|
                    config['vimoutdir'] = value
                end

                opts.on('--[no-]helptags', 'Build the helptags file') do |value|
                    config['helptags'] = nil unless value
                end

                opts.on('-n', '--[no-]dry-run', 'Don\'t actually run any commands; just print them') do |bool|
                    config['dry'] = bool
                end

                opts.on('--print-config', 'Print the configuration and exit') do |bool|
                    puts "Configuration file: #{config['configfile']}"
                    puts YAML.dump(config)
                    exit
                end

                opts.on('--print-version NAME', String, 'Print the plugins current version number') do |value|
                    recipe = File.join(config['outdir'], "#{value}.recipe")
                    puts Vimball.new(config).get_version(recipe, value)
                    exit
                end

                opts.on('--print-saved-version NAME', String, 'Print the plugins last saved version number') do |value|
                    yaml = File.join(config['outdir'], "#{value}.yml")
                    if File.exist?(yaml)
                        script_def = YAML.load_file(yaml)
                        puts script_def['version']
                    end
                    exit
                end

                opts.on('-R', '--[no-]recipe', 'On install, save the recipe in DESTDIR/vimballs/recipes') do |bool|
                    config['save_recipes'] = bool
                end

                opts.on('-r', '--[no-]record', 'Save record in .VimballRecord') do |bool|
                    config['record'] = bool
                end

                opts.on('--[no-]repo', 'Install as single directory in a code repository') do |bool|
                    config['repo'] = true
                end

                opts.on('-u', '--[no-]update', 'Create VBA only if it is outdated') do |bool|
                    config['update'] = bool
                end

                opts.on('-y', '--save-yaml [YAML]', String, 'Save a YAML script definition that can be fed to vimscriptuploader.rb') do |value|
                    config['script_def_yaml'] = value
                end

                opts.on('-z', '--gzip', 'Save as vba.gz') do |value|
                    config['compress'] = value
                end


                opts.separator ' '
                opts.separator 'Other Options:'

                opts.on('--debug', 'Show debug messages') do |v|
                    $DEBUG   = true
                    $VERBOSE = true
                    AppLog.set_level
                end

                opts.on('-v', '--verbose', 'Run verbosely') do |v|
                    $VERBOSE = true
                    AppLog.set_level
                end

                opts.on('--version', 'Version number') do |bool|
                    puts VERSION
                    exit 1
                end

                opts.on_tail('-h', '--help', 'Show this message') do
                    puts opts
                    exit 1
                end
            end
            $logger.debug "command-line arguments: #{args}"

            config['files'] ||= []
            rest = opts.parse!(args)
            if rest.size == 1 && rest.last =~ /\.vba$/
                config['cmd'] = 'install'
                config['files'] << rest.shift
            else
                config['cmd'] = rest.shift
                config['files'].concat(rest)
            end
            config['vimoutdir'] ||= config['outdir']

            return Vimball.new(config)

        end


        protected


        def read_config(config)
            file = config['configfile']
            until @configs.include?(file)
                @configs << file
                if File.readable?(file)
                    $logger.debug "Read configuration from #{file}"
                    config.merge!(YAML.load_file(file))
                    file = config['configfile']
                    break
                end
            end
        end

    end


    def initialize(config)
        @config = config
    end


    def run
        if ready?

            meth = "do_#{@config['cmd']}"
            @config['files'].each do |file|
                @repo = nil
                $logger.debug "#{@config['cmd']}: #{file}"
                if respond_to?(meth)
                    send(meth, file)
                else
                    $logger.fatal "Unknown command: #{@config['cmd']}"
                    exit 5
                end
            end

            post = "post_#{@config['cmd']}"
            send(post) if respond_to?(post)

        end
    end


    def ready?

        unless @config['vimfiles'] and File.directory?(@config['vimfiles'])
            $logger.fatal "Where are your vimfiles?"
            exit 5
        end

        cmds = ['vba', 'install', 'list']
        unless cmds.include?(@config['cmd'])
            $logger.fatal "Command must be one of: #{cmds.join(', ')}"
            exit 5
        end

        if @config['files'].empty?
            $logger.fatal "No input files"
            exit 5
        end

        return true

    end


    def do_vba(recipe)

        vimball = [HEADER]

        files = File.readlines(recipe)
        name = File.basename(recipe, '.recipe')
        vbafile = File.join(@config['outdir'], name + '.vba')
        vbafile << '.gz' if @config['compress']
        

        if @config['update'] and File.exist?(vbafile)
            vba_mtime = File.mtime(vbafile)
            $logger.debug "MTIME VBA: #{vbafile}: #{vba_mtime}"
            if files.all? {|file|
                file = file.strip
                filename = File.join(@config['vimfiles'], file)
                filename1 = filename_on_disk(name, file, filename)
                unless File.exist?(filename1)
                    $logger.error "File does not exist: #{filename1}"
                    return
                end
                mtime = File.mtime(filename1)
                older = mtime <= vba_mtime
                $logger.debug "MTIME: #{filename1}: #{mtime} => #{older}"
                older
            }
                $logger.info "VBA is up to date: #{vbafile}"
                return
            end   
        end

        files.each do |file|
            file = file.strip
            unless file.empty?
                filename = File.join(@config['vimfiles'], file)
                filename1 = filename_on_disk(name, file, filename)
                if File.readable?(filename1)
                    content = File.readlines(filename1)
                else
                    $logger.error "File does not exist: #{filename}"
                    return
                end
                # content.each do |line|
                #     line.sub!(/(\r\n|\r)$/, "\n")
                # end

                filename = clean_filename(filename)

                rewrite = @config['rewrite']
                if rewrite
                    rewrite.each do |pattern, replacement|
                        rx = Regexp.new(pattern)
                        filename.gsub!(rx, replacement)
                    end
                end

                vimball << "#{filename}	[[[1\n#{content.size}\n"
                vimball.concat(content)
            end
        end

        ensure_dir_exists(File.dirname(vbafile))
        vimball = vimball.join

        if @config['compress']
            $logger.warn "Save as: #{vbafile}"
            unless @config['dry']
                Zlib::GzipWriter.open(vbafile) do |gz|
                    gz.write(vimball)
                end
            end
        else
            $logger.warn "Save as: #{vbafile}"
            file_write(vbafile, 'w') do |io|
                io.puts(vimball)
            end
        end

        if @config.has_key?('script_def_yaml')
            get_script_def(name)
        end

    end


    def do_install(file)
        filebase, vimball = read_vimball(file)
        installdir = get_installdir(filebase)
        $logger.warn "Install #{file} in #{installdir}"

        recipe = with_vimball(vimball) do |basename, content|
            filename = File.join(installdir, basename)
            ensure_dir_exists(File.dirname(filename))
            $logger.info "Write #{filename}"
            file_write(filename) do |io|
                io.puts(content.join)
            end
        end

        if @config['save_recipes']
            recipefile = File.join(@config['installdir'], 'vimballs', 'recipes', filebase + '.recipe')
            $logger.debug "Save recipe file: #{recipefile}"
            ensure_dir_exists(File.dirname(recipefile))
            file_write(recipefile) do |io|
                io.puts recipe.join("\n")
            end
        end

        if @config['record']
            record = File.join(@config['vimfiles'], '.VimballRecord')
            $logger.debug "Save vimball-record information: #{record}"
            file_write(record, 'a') do |io|
                info = recipe.map {|r| 
                    rr = File.expand_path(File.join(@config['vimoutdir'], r))
                    "call delete(#{rr.inspect})"
                }.join('|')
                io.puts "#{filebase}.vba: #{info}"
            end
        end

    end


    def post_install
        helptags = @config['helptags']
        if helptags.is_a?(String) and !helptags.empty?
            helptags = helptags % File.join(@config['outdir'], 'doc')
			if File.exist?(helptags)
				$logger.info "Create helptags: #{helptags}"
				`#{helptags}` unless @config['dry']
			end
        end
    end


    def do_list(file)
        filebase, vimball = read_vimball(file)
        $logger.info "List #{file}"
        recipe = with_vimball(vimball)
        puts recipe.join("\n")
    end


    def read_vimball(file)
        vimball = nil
        if file =~ /\.gz$/
            filebase = File.basename(File.basename(file, '.gz'), '.*')
            File.open(file) do |f|
                gzip = Zlib::GzipReader.new(f)
                vimball = gzip.readlines
            end
        else
            filebase = File.basename(file, '.*')
            vimball = File.readlines(file)
        end
        header = vimball.shift(3).join
        if header != HEADER
            $logger.fatal "Not a vimball: #{file}"
            exit 5
        end
        return filebase, vimball
    end


    # Takes optional block as argument.
    def with_vimball(vimball)
        recipe = []
        until vimball.empty?

            fileheader = vimball.shift
            nlines = vimball.shift.to_i
            m = /^(.*?)\t\[\[\[1$/.match(fileheader)
            if m and nlines > 0
                basename = m[1]
                recipe << basename
                content = vimball.shift(nlines)
                yield(basename, content) if block_given?
            else
                $logger.fatal "Error when parsing vimball: #{file}"
                exit 5
            end

        end
        return recipe
    end


    def get_installdir(vimball)
        installdir = @config['installdir']
        if @config['repo']
            installdir = File.join(installdir, @config['repodir'], File.basename(vimball, '.*'))
        end
        installdir
    end

    def ensure_dir_exists(dir)
        unless @config['dry'] or File.exist?(dir) or dir.empty? or dir == '.'
            parent = File.dirname(dir)
            unless File.exist?(parent)
                ensure_dir_exists(parent)
            end
            $logger.info "mkdir #{dir}"
            Dir.mkdir(dir)
        end
    end

    def file_write(filename, mode='w', &block)
        $logger.info "Write file: #{filename}"
        unless @config['dry']
            if File.exist?(filename) and mode !~ /^a/
                $logger.warn "Overwrite existing file"
            end
            File.open(filename, mode, &block)
        end
    end


    def clean_filename(filename)
        filename = Pathname.new(filename).relative_path_from(Pathname.new(@config['vimfiles'])).to_s
        filename.gsub!(/\\/, '/')
        return filename
    end


    def filename_on_disk(name, file, filename)
        if File.exist?(filename)
            return filename
        else
            case @repo
            when String
                return File.join(@repo, file)
            when nil
                for root in @config['roots'] || []
                    if @config['repo_fmt']
                        repo_name = @config['repo_fmt'] % name
                    else
                        repo_name = name
                    end
                    repo = File.join(root, repo_name)
                    filename1 = File.join(repo, file)
                    if File.exist?(filename1)
                        @repo = repo
                        return filename1
                    end
                end
                @repo = false
            end
            r = @config['replacements']
            if r and r[filename]
                return r[filename]
            else
                g = @config['gsub']
                if g
                    for rxs, rpl in g
                        filename = filename.gsub(Regexp.new(rxs), rpl)
                    end
                end
                return filename
            end
        end
    end


    def get_script_def(name)
        recipe = File.join(@config['outdir'], "#{name}.recipe")
        vimball = File.join(@config['outdir'], "#{name}.vba")
        script_yml = @config['script_def_yaml'] || File.join(@config['outdir'], "#{name}.yml")
        if File.exist?(script_yml)
            script_def = YAML.load_file(script_yml)
        else
            script_def = {}
        end

        script_id = get_id(name, recipe)
        if script_id.nil?
            $logger.error "No Script ID found"
        elsif (script_def.has_key?('id') and script_def['id'] != script_id)
            $logger.error "Script ID mismatch: Expected #{script_def['id']} but got #{script_id}"
            return nil
        end
        script_def['id'] = script_id

        script_def['version'] = get_version(recipe, name)
        if script_def['version'].nil?
            return nil
        end

        script_def['message'] = ""
        if @repo and File.exist?(File.join(@repo, '.git'))
            FileUtils.cd(@repo) do
                tags = `git tag`.split(/\n/)
                unless tags.empty?
                    tags.sort! do |a, b|
                        if a =~ /^v?(\d+)$/
                            a = $1
                            af = a.to_f / 100
                        else
                            af = a.to_f
                        end
                        if b =~ /^v?(\d+)$/
                            b = $1
                            bf = b.to_f / 100
                        else
                            bf = b.to_f
                        end
                        if af == 0 and bf == 0
                            a <=> b
                        else
                            af <=> bf
                        end
                    end
                    latest_tag = tags.last
                    $logger.debug "git log --oneline #{latest_tag}.."
                    changes = `git log --oneline #{latest_tag}..`
                    unless changes.empty?
                        changes = changes.split(/\n/).map do |line|
                            line.sub(/^\S+/, '-')
                        end
                        if @config['ignore_git_messages_rx']
                            ignore_git_messages_rx = Regexp.new(@config['ignore_git_messages_rx'])
                            changes.delete_if {|line| line =~ ignore_git_messages_rx}
                        end
                        script_def['message'] = changes.join("\n")
                        script_def['message'] << "\n" unless script_def['message'].empty?
                    end
                end
            end
        end
        # p "DBG", script_def['message']
        if script_def['message'].empty? and @config.has_key?('history_fmt')
            script_def['message'] = @config['history_fmt'] % name
            script_def['message'] << "\n"
        end
        vba = File.open(vimball, 'rb') {|io| io.read}
        script_def['message'] << "MD5 checksum: #{Digest::MD5.hexdigest(vba)}"

        script_def['file'] = vimball

        File.open(script_yml, 'w') {|io| YAML.dump(script_def, io)}
        return script_def
    end


    def get_id(name, recipe)
        File.readlines(recipe).each do |line|
            file = line.chomp
            filename = filename_on_disk(name, file, file)
            bname = File.basename(filename)
            File.readlines(filename).each do |line|
                if line.chomp =~ /^" GetLatestVimScripts: (\d+) +\d+ +(:AutoInstall: +)?#{bname}$/
                    id = $1
                    if id and !id.empty? and id.to_i != 0 and id =~ /[1-9]/
                        $logger.debug "#{name}: Script ID is ##{id}"
                        return id
                    end
                end
            end
        end
        return nil
    end


    def get_version(recipe, name)
        $logger.debug "Get version number for #{name} (#{recipe})"
        File.readlines(recipe).each do |line|
            file = line.chomp
            filename = filename_on_disk(name, file, file)
            $logger.debug "Get version number in #{filename}"
            File.readlines(filename).each do |line|
                if line.chomp =~ /^let (g:)?loaded_#{name} = (\d+)$/
                    version = $2.to_i
                    major = version / 100
                    minor = version - major * 100
                    majmin = "%d.%02d" % [major, minor]
                    $logger.debug "#{name}: Version number is #{majmin}"
                    return majmin
                end
            end
        end
        $logger.error "Cannot find version number: #{recipe}"
        return nil
    end

end


if __FILE__ == $0

    Vimball.with_args(ARGV).run

end


# Local Variables:
# revisionRx: VERSION\s\+=\s\+\'
# End:
