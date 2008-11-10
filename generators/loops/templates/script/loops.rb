#!/usr/bin/env ruby

require 'optparse'
require File.dirname(__FILE__) + '/../config/boot'
require File.dirname(__FILE__) + '/../config/environment'

$LOAD_PATH.unshift("vendor/plugins/loops/lib")

LOOPS_ROOT = Rails.root
LOOPS_CONFIG_FILE = LOOPS_ROOT + "/config/loops.yml"

require 'loops'
require 'loops/daemonize'

# Default options
options = { 
  :daemonize => false, 
  :loops => [], 
  :all_loops => false, 
  :list_loops => false, 
  :pid_file => nil, 
  :stop => false 
}

# Parse command line options
opts = OptionParser.new do |opt|
  opt.banner = "Usage: loops [options]"
  opt.separator ""
  opt.separator "Specific options:"

  opt.on('-d', '--daemonize', 'Daemonize when all loops started.') { |v| options[:daemonize] = v }
  opt.on('-s', '--stop', 'Stop daemonized loops if running.') { |v| options[:stop] = v }
  opt.on('-p', '--pid=file', 'Override loops.yml pid_file option.') { |v| options[:pid_file] = v }
  opt.on('-l', '--loop=loop_name', 'Start specified loop(s) only') { |v| options[:loops] << v }
  opt.on('-a', '--all', 'Start all loops') { |v| options[:all_loops] = v }
  opt.on('-L', '--list', 'Shows all available loops with their options') { |v| options[:list_loops] = v }

  opt.on_tail("-h", "--help", "Show this message") do
    puts(opt)
    exit(0)
  end

  opt.parse!(ARGV)
end

# Load config file
puts "Loading config..."
Loops.load_config(LOOPS_CONFIG_FILE)
options[:pid_file] ||= (Loops.global_config['pid_file'] || "/var/run/loops.pid")
options[:pid_file] = Rails.root + "/" + options[:pid_file] unless options[:pid_file] =~ /^\//

# Stop loops if requested
if options[:stop]
  STDOUT.sync = true
  raise "No pid file or no stale pid file!" unless Loops::Daemonize.check_pid(options[:pid_file])
  pid = Loops::Daemonize.read_pid(options[:pid_file])
  print "Killing the process: #{pid}: "
  loop do
    Process.kill('SIGTERM', pid)
    sleep(1)
    break unless Loops::Daemonize.check_pid(options[:pid_file])
    print(".")
  end
  puts " Done!"
  exit(0)
end

# List loops if requested
if options[:list_loops]
  puts "Available loops:"
  Loops.loops_config.each do |name, config|
    puts "Loop: #{name}" + (config['disabled'] ? ' (disabled)' : '')
    config.each do |k,v|
      puts " - #{k}: #{v}"
    end
  end
  puts
  exit(0)
end

# Ignore --loop options if --all parameter passed
options[:loops] = :all if options[:all_loops]

# Check what loops we gonna run
if options[:loops] == []
  puts opts
  exit(0)
end

# Pid file check
raise "Can't start, another process exists!" if Loops::Daemonize.check_pid(options[:pid_file])

# Daemonization
app_name = "loops monitor: #{ options[:loops].join(' ') rescue 'all' }\0"
Loops::Daemonize.daemonize(app_name) if options[:daemonize]

# Pid file creation
Loops::Daemonize.create_pid(options[:pid_file])

# Workers processing
puts "Starting workers"
Loops.start_loops!(options[:loops])

# Workers exited, cleaning up
puts "Cleaning pid file..."
File.delete(options[:pid_file]) rescue nil
