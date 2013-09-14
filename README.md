About Spikor
============

Spikor is a node terminus for Puppet that contructs a dynamic node specific environment and is made for a workflow where git each branch corresponds to a Puppet environment.
It delegates the actual node classification to another node terminus like the exec one for example so it doesn't do any node classification of its own.

What it needs
-------------

Spikor requires a (bare) git repository, which can contain hiera data and also can contain some modules which should be present on all hosts. This git repo needs to be readable and writeable by the `puppet` user and the location set in the spikor configuration file.

Spikor will not automatically fetch this git repository, you will need to configure some replication mechanism outside of spikor to keep it up to date.

How it works
------------

When a node requests a catalog or node object Spikor will consult the configured node terminus (in the spikor configuration file) for classes, parameters and environment of the node.

Then it will go on and checkout the branch of the git repository that corresponds to the environment that was requested into a node specific path (certname plus a timestamp).

Depending on if you have set it to lookup parameters from hiera or from the node terminus it will get either the `modules` key from hiera or the `modules` parameter from the node terminus. Then it will use the puppet module tool to install the specified modules into the node specific environment that it just created.

It will then return the new environment name to the agent which will restart with a new catalog request against the new environment. This time spikor will see that the environment directory already exists and will just let the node run against it.

Configuration
-------------

The configuration file for spikor is spikor.yaml in the puppet confdir, typically `/etc/puppet/spikor.yaml`.

`repository`: The path to the bare git repository. Defaults to `$confdir/repositories/puppet.git`

`environmentpath`: The path where spikor should create the environment directories. Defaults to `$confdir/environments`

`moduledir`: The directory inside the environment where modules should be installed. Defaults to `modules`

`git`: The path to the git command spikor should use. Defaults to `git`

`node_terminus`: The node terminus to proxy to. Defaults to `exec`

`module_config`: Where spikor should get modules to install from, should be either `hiera` or `node_terminus`. Defaults to `hiera`
