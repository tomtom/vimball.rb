vimball.rb
==========

The vimball.rb ruby script that allows user to create, install, and list 
the contents of 
[vimballs](http://www.vim.org/scripts/script.php?script_id=1502).


Configuration
-------------

Configuration is done via yaml files:

* `VIMFILES/vimballs/config_${hostname}.yml`
* or `VIMFILES/vimballs/config.yml`

Example configuration file:

    --- 
    vimfiles: /home/foo/.vim/
    installdir: /home/foo/.vim/
    compress: false
    helptags: gvim --cmd "helptags %s|quit"
    username: foo
    password: bar
    history_fmt: Please see http://github.com/foo/%s_vim/commits/master/
    ignore_git_messages_rx: ^- (readme|docs|misc|meta|etc|minor)$
    roots:
      - /home/foo/.vim/bundle


Examples
--------

Create a vimball:

    vimball.rb vba myplugin.recipe

Create vimballs if a file has changed:

    vimball.rb -u vba myplugin.recipe

Create a vimball and upload it to vim.org with 
[vimscriptuploader.rb](http://github.org/tomtom/vimscriptuploader.rb):

    rm myplugin.yml || echo ignore error
    vimball.rb -u --save-yaml -- vba myplugin.recipe
    # myplugin.yml is created by vimball.rb
    # A more sophisticated solution wouldn't remove the older yaml file 
    # but compare timestamps.
    if [ -e myplugin.yml ]; then
        vimscriptuploader.rb --user foo --password bar myplugin.yml
    fi

Install a vimball:

    vimball.rb install myplugin.vba

Install a vimball as a "bundle" (i.e. in its own directory under 
`~/.vim/bundle`):

    vimball.rb --repo install myplugin.vba


Uploading vimballs to vim.org
-----------------------------

vimball.rb doesn't upload files by itself but it can save a script 
definition as yaml file, which can be fed to 
[vimscriptuploader.rb](http://github.org/tomtom/vimscriptuploader.rb).

In order to make this work, your scripts have to comply to the following 
convention:

* At least one file must contain a `GetLatestVimScripts` tagline. If the 
  file is "foo.vim", the line must look somewhat like:

    `" GetLatestVimScripts: 123 0 :AutoInstall: foo.vim`

* At least one file must set a global `loaded_PLUGIN` variable. If the 
  plugin is "bar", the corresponding line must look like:

    `let loaded_bar = VERSION_NUMBER`

  where `VERSION_NUMBER` is an integer that complies with vim's version 
  numbering system (see :help v:version).

* If you use tags, vimball.rb will compile the comment version from the 
  commit messages since the latest tag. The following tag formats are 
  supported (e.g. if the version number is 1.02): v102, 102, 1.02.

  If you don't use tags, version comments are limited to simple messages 
  if the configuration file defines a field `history_fmt` that must 
  contain one `%s`, which will be filled in with the plugin name, the 
  formatted string will be posted as version comment.

  The MD5 checksum will be added to the version comment.


Dependencies
------------

* ruby 1.8
* git (to extract log messages and tags for the YAML script definition)


<!-- 2010-11-01; @Last Change: 2010-11-01. -->
<!-- vi: ft=markdown:tw=72:ts=4 -->
