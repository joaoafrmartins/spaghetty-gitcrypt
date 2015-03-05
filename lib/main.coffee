async = require 'async'

{ EOL } = require 'os'

{ resolve } = require 'path'

stash = require 'png-stash'

ACliCommand = require 'a-cli-command'

class Gitcrypt extends ACliCommand

  command:

    name: "gitcrypt"

    options:

      salt:

        type: "string"

        description: [
          "the salt used for encrypting",
          "the repository"
        ]

      pass:

        type: "string"

        description: [
          "the encryption password"
        ]

      cipher:

        type: "string"

        default: "aes-256-ecb"

        description: [
          "the cipher type used by openssl"
        ]

      doodle:

        type: "string"

        description: [
          "save a configuration object",
          "inside a '.png' using lsb",
          "steganography"
        ]

      templates:

        type: "array"

        default: ["package-init-readme"]

        description: [
          "calls package-init in order",
          "to force the creation of a",
          "README.md and a doodle.png",
          "file used for saving the",
          "configuration for seamless",
          "decryption"
        ]

      force:

        type: "boolean"

        description: [
          "defines whether or not",
          "the command should be called",
          "in interactive mode"
        ]

      extensions:

        type: "array"

        default: ["*.coffee", "*.json", "*.cson", "*.js", "*.less", "*.css", "*.html", "*.hbs"]

        description: [
          "an array of files extensions wich",
          "should be marked for encryption"
        ]

      gitattributes:

        type: "string"

        default: ".git/info/attributes"

        description: [
          "the gitattributes file location",
          "defaults to '.git/info/attributes'",
          "but can also be specified as a",
          "'.gitattributes' file"
        ]

      gitconfig:

        type: "boolean"

        description: [
          "configure git repository",
          "for seamless encryption and",
          "descryption"
        ]

      commit:

        type: "boolean"

        description: [
          "specifies if the repository",
          "should be pushed after configuration"
        ]

      encrypt:

        type: "boolean"

        triggers: ["salt", "pass", "cipher", "templates", "extensions", "doodle", "gitattributes", "gitconfig"]

        description: [
          "encrypt a git repository",
          "using openssl"
        ]

      decrypt:

        type: "boolean"

        triggers: ["doodle", "gitattributes", "gitconfig"]

        description: [
          "reset repository head",
          "in order to decrypt files"
        ]

  "salt?": (command, next) ->

    @shell

    if not test "-d", resolve ".git"

      return next "error: not a git repository", null

    { salt } = command.args

    if salt then return next null, "salt: #{salt}"

    md5 = "$(which md5 2>/dev/null || which md5sum 2>/dev/null)"

    bin = "head -c 10 < /dev/random | #{md5} | cut -c-16"

    @exec

      bin: bin

      silent: true

    , (err, salt) ->

      salt = salt.replace /\n$/, ''

      if err then return next "error generating salt: #{err}"

      command.args.salt = salt

      next null, "salt: #{salt}"

  "pass?": (command, next) ->

    { pass } = command.args

    if pass then return next null, "pass: #{pass}"

    chars = "!@#$%^&*()_A-Z-a-z-0-9"

    bin = "cat /dev/urandom | LC_ALL='C' tr -dc '#{chars}' | head -c32"

    @exec

      bin: bin

      silent: true

    , (err, pass) ->

      pass = pass.replace /\n$/, ''

      if err then return next "error generating pass: #{err}"

      command.args.pass = pass

      next null, "pass: #{pass}"

  "templates?": (command, next) ->

    @shell

    { templates, force, doodle } = command.args

    if not templates then return next "error generating doodle: #{doodle}", null

    args = ["init", "--templates", JSON.stringify templates]

    if force then args.push "--force"

    @cli.run args, next

  "doodle?": (command, next) ->

    @shell

    doodletemplate = resolve pwd(), 'doodle.png'

    if doodle

      doodle = resolve doodle

      if not test "-e", doodle

        mv doodletemplate, doodle

    else if not doodle then doodle = doodletemplate

    if test "-e", doodle

      command.args.doodle = doodle

    else return next "error doodle: #{doodle}"

    { encrypt, decrypt, doodle } = command.args

    if encrypt

      { extensions, salt, pass, cipher } = command.args

      stash doodle, (err, payload) ->

        if err then return next "error reading doodle: #{err}"

        data = JSON.stringify

          salt: salt

          pass: pass

          cipher: cipher

          extensions: extensions

        data = "#{data.length}#{data}"

        payload.write data

        payload.save (err) ->

          if err then return next "error saving doodle: payload #{err}", null

          next null, "payload: #{data}"

    else if decrypt

      stash doodle, (err, payload) ->

        try

          length = payload.read 0, 3

          data = payload.read(3, Number(length.toString())).toString()

          data = JSON.parse data

          for k, v of data then command.args[k] = v

          return next null, "payload: #{data}"

        catch err then return next err, null

    else return next "error configuring doodle data: #{doodle}", null

  "gitconfig?": (command, next) ->

    @shell

    if not test "-d", resolve ".git"

      return next "error: not a git repository", null

    { extensions, salt, pass, cipher, gitattributes, commit } = command.args

    gitattributes = resolve gitattributes

    data = [""]

    for extension in extensions

      data.push "#{extension} filter=encrypt diff=encrypt"

    data.push "[merge]"

    data.push "\trenormalize=true"

    if test "-f", gitattributes

      if contents = cat(gitattributes)

        data.unshift contents

    data.push ""

    data = data.join EOL

    data.to gitattributes

    _salt = "$(git config gitcrypt.salt)"

    _pass = "$(git config gitcrypt.pass)"

    _cipher = "$(git config gitcrypt.cipher)"

    clean = "openssl enc -base64 -#{_cipher} -S #{_salt} -k #{_pass}"

    smudge = "openssl enc -d -base64 -#{_cipher} -k #{_pass} 2> /dev/null || cat"

    diff = "openssl enc -d -base64 -$CIPHER -k #{_pass} -in $1 2> /dev/null || cat $1"

    config =

      "gitcrypt.salt": "'#{salt}'"

      "gitcrypt.pass": "'#{pass}'"

      "gitcrypt.cipher": "'#{cipher}'"

      "filter.encrypt.smudge": "'#{smudge}'"

      "filter.encrypt.clean": "'#{clean}'"

      "diff.encrypt.textconv": "'#{diff}'"

    series = []

    Object.keys(config).map (name) =>

      value = config[name]

      series.push (done) =>

        @exec

          bin: "git config --add #{name} #{value}"

          silent: true

        , (err, res) =>

          if err then return done err, null

          done null, res

    return async.series series, next

  "execute?": (command, next) ->

    @shell

    if not test "-d", resolve ".git"

      return next "error: not a git repository", null

    { encrypt, decrypt } = command.args

    if encrypt

      { commit } = command.args

      if commit

        series = []

        series.push (done) =>

          @exec

            bin: "git add .",

          , (err, res) =>

            if err then return done err, null

            done null, res

        series.push (done) =>

          @exec

            bin: "git commit -am 'R.I.P.'",

          , (err, res) =>

            if err then return done err, null

            done null, res

        series.push (done) =>

          @exec

            bin: "git push origin master",

          , (err, res) =>

            if err then return done err, null

            done null, res

        return async.series series, next

    else if decrypt

      bin = "git reset --hard HEAD"

      @exec bin, (err, res) ->

        if err then return next err, null

        next null, res

    else return next "error configuring gitcrypt", null

module.exports = Gitcrypt
