#! /usr/bin/env ruby
# encoding: UTF-8

# Copyright 2015 Chen Ruichao <linuxer.sheep.0x@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.







# This file contains dirty code for testing.  It is NOT a good example.

# XXX CWD must be output dir

# config (for ease of changing, not for "customization")
INPUT     = '../test-spec'
RUNNER    = '../run-tests.bash'
JARS      = ['../gitlet.jar', '../gitlet-app.jar']
GITLET    = 'java -jar ../../gitlet.jar'
GITLETAPP = 'java -jar ../../gitlet-app.jar'
BOTHMODES = false
MODE      = 'CS61B'



require 'fileutils'

def compile_all
  cnt = 0
  tests = []
  while gets
    $_.chomp!
    next if $_ == '' || $_[0] == '#'
    unless '====================' == $_[0, 20]
      warn 'Invalid line: '+$_
      $fail = true
      next
    end
    name = $_[21..-1]
    cnt += 1

    filename = cnt.to_s
    filename += " - #{name}" if name =~ /\A[ a-zA-Z0-9()]+\z/
    compile_case(filename)
    tests << filename
  end

  write_testrunner(tests)
end

def write_testrunner(tests)
  open(RUNNER, ?w, 0740) do |ios|
    ios.write("#! /usr/bin/env bash\n\n")
    JARS.each {|f|
      ios.puts("[[ -e #{f} ]] || { echo #{f} missing >&2; exit 1; }")
      break unless BOTHMODES
    }
    ios.write("\ntypeset -i failcnt=0\nresultbar=''\n")
    ios.write("function record() { if [[ $1 == 0 ]]; then resultbar+=$'\\e[0m\\e[32m✓'; else failcnt+=1; resultbar+=$'\\e[1m\\e[31m✗'; fi; }\n\n")
    tests.each_with_index {|t, i|
      ios.puts("resultbar+=' '") if i%10 == 0
      ios.puts("echo '==================== #{t} ===================='",
               "./'#{t}'; record $?; echo")
    }
    ios.write("\necho; echo Results: $resultbar$'\\e[0m'; echo \"$failcnt failure(s) out of\"; echo '#{tests.size} total testcase(s)'")
  end
end

def compile_case(filename)
  input = read_case                     # read until the next testcase
  data = CaseParser.new(input).parse    # TODO bad naming: data doesn't mean anything
  write_case(filename, data) if data    # otherwise skip the bad testcase
end

# empty lines and comments are striped
def read_case
  lines = []

  while gets
    $_.chomp!
    break if $_ == ''
    next if $_[0] == '#'
    $_.slice! 0 if $_.start_with? '=>'
    $_.slice! 1 if $_.length >= 2 && $_[1] == ' '
    lines << $_
  end

  lines
end

def write_case(filename, data)
  dir = filename + '.d'
  FileUtils.mkdir_p(dir)

  open(filename, ?w, 0740) do |f|
    f.write("#! /usr/bin/env bash\n\n")
    f.puts 'function abort() {'
    f.puts '    printf \'%s\n\' "$1"'
    f.puts '    exit 1'
    f.puts '}'
    f.puts
    f.puts 'mkdir -p actual || abort "Failed to create test directory"'
    f.puts
    f.puts 'function fail() {'
    f.puts "    { rm -rf '../#{dir}/actual' && mv ../actual '../#{dir}/'; } || abort 'Failed to save program output'"
    f.puts '    abort "$1"'
    f.puts '}'
    f.puts

    # TODO use shared .err and .out when identical
    for mode in ['CS61B', 'APP']
      next if !BOTHMODES && mode != MODE
      write_case_mode(filename, f, mode, data)
    end
  end
end

# TODO arg passing is ugly
def write_case_mode(filename, f, mode, data)
  f.puts("# ==================== #{mode} mode ====================")

  if mode == 'CS61B'
    gitlet = GITLET
    whichdata = 0
    suffix = ''
  else
    gitlet = BOTHMODES ? GITLETAPP : GITLET
    whichdata = -1
    suffix = '.app'
  end

  f.puts '{ rm -rf workingdir && mkdir workingdir; } || abort "Failed to create test directory"'
  f.puts 'cd workingdir || abort "Failed to enter test directory"'
  f.puts

  run_cnt = 0
  for type, cmd, *cmddata in data
    case type
      when :shell
        f.puts 'cat <<EOF'
        f.puts 'Running:    ' + cmd
        f.puts 'EOF'
        f.puts cmd

      when :gitlet
        termstat, stdout, stderr = cmddata[whichdata]
        run_cnt += 1

        need_confirm = false
        if mode == 'CS61B'
          %w(checkout reset merge rebase i-rebase pull).each {|c|
            need_confirm = true if cmd.start_with? (c+' ')
          }
        end

        f.puts "cat <<EOF"
        f.puts "Running:    gitlet #{cmd}"
        f.puts "EOF"
        f.write "echo yes | " if need_confirm
        f.puts "#{gitlet} #{cmd}" + ' > ../actual/stdout 2> ../actual/stderr'

        f.puts "TESTERVAR_TERMSTAT=$?"
        f.puts "[[ $TESTERVAR_TERMSTAT == #{termstat} ]] " +
               "|| fail \"Expected \\$?: #{termstat} actual: $TESTERVAR_TERMSTAT (run ##{run_cnt})\""

        check_output = proc {|stream, content|
          expected = "#{filename}.d/#{run_cnt}#{suffix}.#{stream}"
          content.unshift("WARNING: Using APP mode, not suitable for CS 61B submission") if stream == 'err' && mode == 'APP'
          content.unshift("Warning: The command you entered may alter the files in your working directory. Uncommitted changes may be lost. Are you sure you want to continue? (yes/no)") if stream == 'out' && need_confirm
          if content.empty?
            f.puts "diff -q ../actual/std#{stream} /dev/null || fail 'Failure: std#{stream} should be empty'"
          else
            open(expected, ?w) {|f2| f2.puts(content) }
            f.puts "diff -q ../actual/std#{stream} ../'#{expected}' || fail 'Failure: std#{stream} differs from expected version'"
          end
        }
        check_output.call('out', stdout)
        check_output.call('err', stderr)

      else # ouch
    end
    f.puts
  end

  f.puts 'cd ..'
  f.puts
end

# TODO a lot of bad naming here
# TODO check if we can handle any bad input (currently we may crash)
class CaseParser
  # @input is used as a stack
  def initialize(input)
    @input = input.reverse
  end

  def peek; @input.last; end
  def pop;  @input.pop;  end

  # return: type or nil
  def peektype
    (peek || '')[0]
  end

  # return: line or nil
  def popline
    (pop || '')[1..-1]
  end
  private :pop, :peek, :peektype, :popline

  # everything above is lowerlevel, below is upperlevel

  class BadInput < RuntimeError; end

  # [ [:shell, 'touch foo'],
  #   [:gitlet, 'init', [0, ['message'], []]],
  #   [:gitlet, 'init', [0, ['61b message'], []], [1, ['app message'], ['APP MODE ERROR!']]],
  #   ...]
  def parse
    data = []

    until @input.empty?
      if peektype == '$'
        data << [:shell, popline]
        next
      end

      unless g = tryparse_gitlet
        msg = "Unexpected line type: #{peektype} (content: #{popline})"
        raise BadInput.new(msg)
      end

      data << ([:gitlet] + g)
    end

    data

  rescue BadInput => e
    warn e  # equiv to: warn(e.message); nil
    $fail = true
    nil
  end


  def tryparse_gitlet
    return nil unless peektype == '%'

    cmd = popline

    ts = tryparse_termstat
    # one set
    ts or return [cmd, [0] + parse_out]
    # two sets
    return [cmd, ([ts] + parse_out), ([parse_termstat] + parse_out)]
  end

  # Fixnum or nil
  def tryparse_termstat
    # TODO to_i: no error checking
    popline.to_i if peektype == '>'
  end

  def parse_termstat
    v = tryparse_termstat
    v or raise BadInput.new('Expecting termstat, got: ' + peek) # TODO peek的结果可能是去掉空格之后的，这可能让用户感到困惑
    v
  end

  # [['std', 'out'], ['std', 'err']]
  def parse_out
    out = []; out << popline while peektype == ':'
    err = []; err << popline while peektype == '!'
    [out, err]
  end
end






$fail = false
$stdin = open(INPUT)
compile_all
fail if $fail

