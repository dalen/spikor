require 'hiera'
require 'puppet/node'
require 'puppet/face'
require 'puppet/indirector/hiera'
require 'yaml'

class Puppet::Node::Spikor < Puppet::Indirector::Hiera
  desc 'Create a dynamic node specific environment. Queries the key "modules" in hiera to find the modules to install.'

  def find(request)
    # Get node object from the configured node_terminus
    node = Puppet::Node.indirection.terminus(spikor_config[:node_terminus].to_sym).find(request)

    Puppet.debug "Spikor: node environment=#{node.environment}"

    # See if we have already created the environment or if we need to create it now
    if File.exist? File.join(spikor_config[:environmentpath], node.environment.to_s)
      name = node.environment.to_s
      create_env = false
    else
      name = request.key.gsub(/\W/, '_') + '_' + Time.now.utc.to_i.to_s
      create_env = true
    end

    if create_env
      ref = git_find_ref spikor_config[:repository], node.environment.to_s
      Puppet.debug "Spikor: using git ref #{ref}"

      # Create a checkout of the repository for the node environment
      path = File.join(spikor_config[:environmentpath], name)
      git_checkout spikor_config[:repository], ref, path

      if :module_config == :hiera
        # Lookup modules to use from hiera using key 'modules'
        facts = Puppet::Node::Facts.indirection.find(request.key)
        if facts
          facts = facts.values
        else
          Puppet.debug "Spikor: could not find facts for #{request.key}"
          facts = {}
        end
        facts['environment'] = name

        modules = hiera.lookup('modules', {}, facts, nil, :hash)
      else
        # Otherwise take the value of the 'modules' parameter/fact
        modules = node.parameters['modules'] || {}
      end
      Puppet.warning "No modules found for #{request.key}" if modules.empty?

      # Install each specified module into the node environment
      moduletool = Puppet::Face[:module, '1']
      modules.each do |modname, mod|
        options = {
          :modulepath  => File.join(path, spikor_config[:moduledir]),
          :environment => node.environment,
        }
        options[:version] = mod['version'] if mod['version']
        result = moduletool.install(modname, options)
        raise result[:error][:oneline] if result[:result] == :failure
      end
    end

    node.environment = name
    node
  end

  private

  def self.spikor_config
    configfile = File.join Puppet.settings[:confdir], 'spikor.yaml'
    config = {
      :repository      => File.join(Puppet.settings[:confdir], 'repositories', 'puppet.git'),
      :environmentpath => File.join(Puppet.settings[:confdir], 'environments'),
      :moduledir       => 'modules',
      :git             => 'git',
      :node_terminus   => :exec,
      :module_config   => :hiera,
    }

    if File.exist?(configfile)
      config.merge! YAML.load_file(configfile)
    else
      Puppet.debug "Config file #{configfile} not found, using Spikor defaults"
    end

    config
  end

  def spikor_config
    @config ||= self.class.spikor_config
  end

  ##
  # Find a git ref matching the environment string. Uses _ as a wildcard character.
  # Throw exception if several refs match.
  #
  # repository  [String] Path to the (bare) git repository
  # environment [String] The Puppet environment name to search for
  # @return     [String] name of the matching ref
  def git_find_ref(repository, environment)
    refs = git_refs(repository).grep Regexp.new('^' + environment.sub('_', '.') + '$')
    raise "Ambiguous environment \"#{environment}\", #{refs.length} git refs matching" if refs.length > 1
    return refs.first if refs.length
    environment
  end

  ##
  # Get a list of all branches and tags from a git repository
  #
  # repository [String] Path to the (bare) git repository
  # @return    [Array]  a list of branches and tags
  def git_refs(repository)
    `#{spikor_config[:git]} --git-dir=#{repository} branch --no-color`.lines.collect do |branch|
      branch.slice(2..-1).chomp
    end.concat `#{spikor_config[:git]} --git-dir=#{repository} tag -l`.lines.collect do |tag|
      tag.chomp
    end
  end

  ##
  # Checkout the specified ref from a git repository into the path specified
  # The path is created if it doesn't exist.
  #
  # repository [String] Path to the (bare) git repository
  # ref        [String] The git ref to checkout
  # path       [String] The path to checkout into
  def git_checkout(repository, ref, path)
    Dir.mkdir(path)
    output = `#{spikor_config[:git]} --git-dir=#{repository} --work-tree=#{path} checkout --force --quiet #{ref} 2>&1`
    raise output.lines.to_a.join(" ") if $?.to_i != 0
  end
end
