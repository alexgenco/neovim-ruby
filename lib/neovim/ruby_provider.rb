require "neovim/ruby_provider/vim"
require "neovim/ruby_provider/buffer_ext"
require "neovim/ruby_provider/window_ext"

module Neovim
  # This class is used to define a +Neovim::Plugin+ to act as a backend for the
  # legacy +:ruby+, +:rubyfile+, and +:rubydo+ Vim commands. It is autoloaded
  # from +nvim+ and not intended to be required directly.
  #
  # @api private
  module RubyProvider
    def self.__define_plugin!
      Thread.abort_on_exception = true

      Neovim.plugin do |plug|
        __define_setup(plug)
        __define_ruby_execute(plug)
        __define_ruby_execute_file(plug)
        __define_ruby_do_range(plug)
        __define_ruby_chdir(plug)
      end
    end

    # Bootstrap the provider client:
    #
    # 1. Monkeypatch +$stdout+ and +$stderr+ to write to +nvim+.
    # 2. Define the +DirChanged+ event to update the provider's pwd.
    def self.__define_setup(plug)
      plug.__send__(:setup) do |client|
        $stdout.define_singleton_method(:write) do |string|
          client.out_write(string)
        end

        $stderr.define_singleton_method(:write) do |string|
          client.err_writeln(string)
        end

        begin
          cid = client.channel_id
          client.command("au DirChanged * call rpcrequest(#{cid}, 'ruby_chdir', v:event)")
        rescue ArgumentError
          # Swallow this exception for now. This means the nvim installation is
          # from before DirChanged was implemented.
        end
      end
    end

    # Evaluate the provided Ruby code, exposing the +Vim+ constant for
    # interactions with the editor.
    #
    # This is used by the +:ruby+ command.
    def self.__define_ruby_execute(plug)
      plug.__send__(:rpc, :ruby_execute) do |nvim, ruby|
        __wrap_client(nvim) do
          eval(ruby, TOPLEVEL_BINDING, "eval")
        end
      end
    end
    private_class_method :__define_ruby_execute

    # Evaluate the provided Ruby file, exposing the +Vim+ constant for
    # interactions with the editor.
    #
    # This is used by the +:rubyfile+ command.
    def self.__define_ruby_execute_file(plug)
      plug.__send__(:rpc, :ruby_execute_file) do |nvim, path|
        __wrap_client(nvim) { load(path) }
      end
    end
    private_class_method :__define_ruby_execute_file

    # Evaluate the provided Ruby code over each line of a range. The contents
    # of the current line can be accessed and modified via the +$_+ variable.
    #
    # Since this method evaluates each line in the local binding, all local
    # variables and methods are available to the user. Thus the +__+ prefix
    # obfuscation.
    #
    # This is used by the +:rubydo+ command.
    def self.__define_ruby_do_range(__plug)
      __plug.__send__(:rpc, :ruby_do_range) do |__nvim, *__args|
        __wrap_client(__nvim) do
          __start, __stop, __ruby = __args
          __buffer = __nvim.get_current_buf

          __update_lines_in_chunks(__buffer, __start, __stop, 5000) do |__lines|
            __lines.map do |__line|
              $_ = __line
              eval(__ruby, binding, "eval")
              $_
            end
          end
        end
      end
    end
    private_class_method :__define_ruby_do_range

    def self.__define_ruby_chdir(plug)
      plug.__send__(:rpc, :ruby_chdir) do |_, event|
        Dir.chdir(event.fetch("cwd"))
      end
    end
    private_class_method :__define_ruby_chdir

    def self.__wrap_client(client)
      Vim.__client = client
      Vim.__refresh_globals(client)

      __with_exception_handling(client) do
        yield
      end
      nil
    end
    private_class_method :__wrap_client

    def self.__with_exception_handling(client)
      begin
        yield
      rescue SyntaxError, LoadError, StandardError => e
        msg = [e.class, e.message].join(": ")
        client.err_writeln(msg.lines.first.strip)
      end
    end

    def self.__update_lines_in_chunks(buffer, start, stop, size)
      (start..stop).each_slice(size) do |linenos|
        _start, _stop = linenos[0]-1, linenos[-1]
        lines = buffer.get_lines(_start, _stop, true)

        buffer.set_lines(_start, _stop, true, yield(lines))
      end
    end
    private_class_method :__update_lines_in_chunks
  end
end

Neovim::RubyProvider.__define_plugin!
