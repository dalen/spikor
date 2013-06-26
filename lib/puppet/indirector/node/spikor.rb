require 'hiera'
require 'puppet/node'
require 'puppet/face'
require 'puppet/indirector/hiera'
require 'yaml'

class Puppet::Node::Spikor < Puppet::Indirector::Hiera
  desc 'Get node information from Hiera. Queries the keys "environment", "classes" and "parameters".'

  def find(request)
    nodeenvironment = request.environment.name.to_s
    Puppet.warning "Spikor: nodeenv=#{nodeenvironment}"

    # See if we have already created the environment or if we need to create it now
    if File.exist? File.join(spikor_config[:environmentpath], nodeenvironment)
      name = nodeenvironment
      create_env = false
    else
      name = request.key.gsub(/\W/, '_') + '_' + Time.now.utc.to_i.to_s
      create_env = true
    end

    path = File.join(spikor_config[:environmentpath], name)

    facts = Puppet::Node::Facts.indirection.find(request.key).values
    facts['environment'] = name

    if create_env
      ref = find_git_ref nodeenvironment
      Puppet.debug "Spikor: using git ref #{ref}"

      git_checkout spikor_config[:repository], ref, path

      modules = hiera.lookup('modules', {}, facts, nil, :hash)
      Puppet.warning "No modules found for #{request.key}" if modules.empty?

      # Install each specified module into the node environment
      moduletool = Puppet::Face[:module, '1']
      modules.each do |modname, mod|
        options = {
          :target_dir => File.join(path, spikor_config[:moduledir]),
        }
        options[:version] = mod['version'] if mod['version']
        result = moduletool.install(modname, options)
        raise result[:error][:oneline] if result[:result] == :failure
      end
    end

    node = Puppet::Node.new(
      request.key,
      :environment => name,
      :parameters  => hiera.lookup('parameters', {}, facts, nil, :hash),
      :classes     => hiera.lookup('classes', [], facts, nil, :array)
    )
    node.fact_merge
    node
  end

  private

  def self.spikor_config
    configfile = File.join Puppet.settings[:confdir], 'spikor.yaml'
    config = {
      :repository => File.join(Puppet.settings[:confdir], 'repositories', 'puppet.git'),
      :environmentpath => File.join(Puppet.settings[:confdir], 'environments'),
      :hieradir => 'hiera-data',
      :moduledir => 'modules',
      :git => 'git',
    }

    if File.exist?(configfile)
      config.merge! YAML.load_file(configfile)
    else
      Puppet.warning "Config file #{configfile} not found, using Spikor defaults"
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
  # @return [String] name of the matching ref
  def find_git_ref(environment)
    refs = git_refs(spikor_config[:repository]).grep Regexp.new(environment.sub '_', '.')
    raise "Ambiguous environment \"#{environment}\", #{refs.length} git refs matching" if refs.length > 1
    return refs.first if refs.length
    environment
  end

  ##
  # @return [Array] a list of branches and tags
  def git_refs(repository)
    `#{spikor_config[:git]} --git-dir=#{repository} branch --no-color`.lines.collect do |branch|
      branch.slice(2..-1).chomp
    end.concat `#{spikor_config[:git]} --git-dir=#{repository} tag -l`.lines.collect do |tag|
      tag.chomp
    end
  end

  def git_checkout(repository, ref, path)
    Dir.mkdir(path)
    output = `#{spikor_config[:git]} --git-dir=#{repository} --work-tree=#{path} checkout --force --quiet #{ref} 2>&1`
    raise output.lines.to_a.join " " if $?.to_i != 0
  end
end
