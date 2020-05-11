#!/usr/bin/ruby

# This file downloads all manual CNF files from
# http://projects.csail.mit.edu/mulsaw/alloy/sat03/index.html
# and runs my modified version of minisat_core to find model counts.
# This was created mostly out of lazines of not wanting to
# rerun the experiment as things changed but also for reproducibility.

require 'net/http'
require 'pathname'

class CNFRetriever
  ROOT_URI = "http://projects.csail.mit.edu/mulsaw/alloy/sat03/index.htm"
  CNF_BASE_URI_REGEX = /cnf\/manual\/[[:alpha:]]+-man-\d{1,2}\.cnf/i
  CNF_URI_REGEX = /cnf\/manual\/(?<name>[[:alpha:]]+)-man-(?<size>\d{1,2})\.cnf/i

  attr_accessor :root_uri, :page_contents

  def initialize
    print "Getting all CNF URI's..."
    @root_uri = URI("http://projects.csail.mit.edu/mulsaw/alloy/sat03/index.html")
    @page_contents = Net::HTTP.get_response(@root_uri).body
    puts "Done"
  end

  def get_all_cnf_links
    uris = @page_contents.scan(CNF_BASE_URI_REGEX)
    base_path = Pathname.new(ROOT_URI).dirname
    uris.map { |uri| base_path + uri }
  end
end

class CNFFile
  @@dir_name = "alloy_cnf_files"

  attr_accessor :name, :size, :contents, :path

  def initialize(uri)
    @name = uri.to_s.match(CNFRetriever::CNF_URI_REGEX)['name']
    @size = uri.to_s.match(CNFRetriever::CNF_URI_REGEX)['size']

    print "Downloading from #{uri.to_s}..."
    to_get = URI(uri.to_s)
    @contents = Net::HTTP.get_response(to_get).body
    puts "Done"
  end

  def write_to_file
    make_cnf_dir_if_needed

    @path = @name + @size + ".cnf"
    @path = @@dir_name + "/" + @path
    print "Writing to file #{@path}..."

    File.delete @path if File.exist? @path

    f = File.open(@path, "w")
    f.write(@contents)
    f.close
    puts "Done"
  end

  def make_cnf_dir_if_needed
    Dir.mkdir @@dir_name unless Dir.exist? @@dir_name
  end
end

class SATInstanceRunner
  MINISAT_OPTS = %w|-verb=2|

  def initialize(abs_path_to_minisat, cnf_file, recorder)
    @file = cnf_file
    @minisat = abs_path_to_minisat
    @output_file = cnf_file.name + cnf_file.size + "-out.txt"

    @command = @minisat + options_to_string + cnf_file.path + " " + @output_file

    @recorder = recorder
  end

  def run
    output = `#{@command}`
    @recorder.handle_output output, @file
  end

  def options_to_string
    MINISAT_OPTS.inject("") do |acc, option|
      acc + " " + option
    end + " "
  end
end

class SATInstanceRecorder
  VARIABLE_RE           = /Number of variables:\s+?(?<num>\d+)/i
  CLAUSES_RE            = /Number of clauses:\s+?(?<num>\d+)/i
  RESTARTS_RE           = /restarts\s+?:\s+?(?<num>\d+)/i
  CONFLICTS_RE          = /conflicts\s+?:\s+?(?<num>\d+)/i
  DECISIONS_RE          = /decisions\s+?:\s+?(?<num>\d+)/i
  PROPOGATIONS_RE       = /propagations\s+?:\s+?(?<num>\d+)/i
  CONFLICT_LITERALS_RE  = /conflict literals\s+?:\s+?(?<num>\d+)/i
  SAT_RE                = /satisfying assignments\s*?:\s+?(?<num>\d+)/i
  MAX_INDEP_RE          = /max indep\s+?:\s+?(?<num>\d+)/i
  TIME_RE               = /CPU time\s+?:\s+?(?<num>\d+)/i

  def self.handle_output(output_txt, cnf_file)
    txt = output_txt

    output = []

    output << cnf_file.name
    output << cnf_file.size

    output << output_txt.match(VARIABLE_RE)["num"]
    output << output_txt.match(CLAUSES_RE)["num"]
    output << output_txt.match(RESTARTS_RE)["num"]
    output << output_txt.match(CONFLICTS_RE)["num"]
    output << output_txt.match(DECISIONS_RE)["num"]
    output << output_txt.match(PROPOGATIONS_RE)["num"]
    output << output_txt.match(CONFLICT_LITERALS_RE)["num"]
    output << output_txt.match(SAT_RE)["num"]
    output << output_txt.match(MAX_INDEP_RE)["num"]
    output << output_txt.match(TIME_RE)["num"]

    puts output.join(",")
  end
end

# Get the Alloy model cnf files
uris = CNFRetriever.new.get_all_cnf_links
files = uris.map { |uri| CNFFile.new(uri) }
files.each { |file| file.write_to_file }

# Run all instances using minisat_core
path_to_my_minisat = "./minisat_core" # Change this

files.each do |file|
  runner = SATInstanceRunner.new(path_to_my_minisat, file, SATInstanceRecorder)
  runner.run
end
