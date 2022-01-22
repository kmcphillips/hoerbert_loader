## USAGE
# ruby hoerbert_loader.rb /media/kevin/HOERBERTINT
##

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "systemcall"
end

require "fileutils"

class LoaderPaths
  attr_reader :base_path, :card_path

  DEFAULT_INPUT_PATHS = {
    "0" => "0 - brown",
    "1" => "1 - red",
    "2" => "2 - navy",
    "3" => "3 - lime",
    "4" => "4 - yellow",
    "5" => "5 - grey",
    "6" => "6 - blue",
    "7" => "7 - orange",
    "8" => "8 - green",
  }.freeze

  def initialize(base_path:, card_path:)
    @base_path = base_path
    @base_path = Pathname.new(@base_path) unless @base_path.is_a?(Pathname)
    @card_path = card_path
    @card_path = Pathname.new(@card_path) if @card_path && !@card_path.is_a?(Pathname)
  end

  def input_root
    base_path.join("input")
  end

  def input_paths
    raise "input_root does not exist" unless File.exists?(input_root)
    (0..8).map(&:to_s).map { |p|
      result = nil
      result = input_root.join(p) if File.exists?(input_root.join(p))
      unless result
        found = Dir.entries(input_root).sort.find { |f| f.start_with?("#{ p } ") }
        result = input_root.join(found) if found
      end
      result = input_root.join(DEFAULT_INPUT_PATHS[p]) unless result
      result
    }
  end

  def output_root
    base_path.join("output")
  end

  def output_paths
    (0..8).map(&:to_s).map { |p| output_root.join(p) }
  end

  def card_paths
    return [] unless card_path
    (0..8).map(&:to_s).map { |p| card_path.join(p) }
  end

  def path_mappings
    Hash[input_paths.zip(output_paths)]
  end
end

class Loader
  attr_reader :paths

  def initialize(base_path:, card_path: nil)
    @paths = LoaderPaths.new(base_path: base_path, card_path: card_path)
  end

  def setup_input
    FileUtils.mkdir(paths.input_root) unless File.exists?(paths.input_root)

    paths.input_paths.map do |p|
      raise "a path is blank" unless p
      FileUtils.mkdir(p) unless File.exists?(p)
      FileUtils.touch(p.join(".keep")) unless File.exists?(p.join(".keep"))
    end
  end

  def setup_output
    FileUtils.rm_rf(paths.output_root) if File.exists?(paths.output_root) # :sweat:
    FileUtils.mkdir(paths.output_root)

    paths.output_paths.each { |p| FileUtils.mkdir(p) }
  end

  def check
    [
      paths.input_root,
      paths.output_root,
      paths.input_paths,
      paths.output_root,
    ].flatten.each do |p|
      raise "#{ p } is a problem" unless File.exists?(p) && File.directory?(p)
    end

    result = SystemCall.call('which', 'sox')
    raise "cannot find 'sox' command" unless result.success?

    if load_card?
      raise "cannot write to card path" unless File.exists?(paths.card_path) && File.directory?(paths.card_path)
    end
  end

  def load_card?
    !!paths.card_path
  end

  def load_card
    raise "cannot load card" unless load_card?
    paths.card_paths.each_with_index do |p, index|
      FileUtils.rm_rf(p) if File.exists?(p)
      FileUtils.cp_r(paths.output_paths[index], p)
    end
  end

  def buttons
    paths.path_mappings.map { |i, o| Button.new(input_path: i, output_path: o) }
  end

  class Button
    attr_reader :input_path, :output_path

    def initialize(input_path:, output_path:)
      @input_path = input_path
      @output_path = output_path
    end

    def name
      File.basename(output_path)
    end

    def files
      entries = Dir.entries(input_path)
      entries = entries.reject { |f| f.start_with?(".") } # TODO: could dig into folders here
      entries = shuffle? ? entries.shuffle : entries.sort

      entries.each_with_index.map { |f, index| AudioFile.new(input: input_path.join(f), output: output_path.join("#{ index }.WAV")) }
    end

    def shuffle?
      f = File.basename(input_path).downcase
      f.include?("shuffle") || f.include?("random")
    end

    class AudioFile
      attr_reader :input, :output

      def initialize(input:, output:)
        @input = input
        @output = output
      end

      def name
        input
      end

      def convert
        # This is right from the Hoerbert docs
	sample_rate = "30982"
	# sample_rate = "32000"
        result = SystemCall.call("sox --buffer 131072 --multi-threaded --no-glob \"#{ input }\" --clobber -r#{ sample_rate } -b 16 -e signed-integer --no-glob \"#{ output }\" remix - gain -n -1.5 bass +1 loudness -1 pad 0 0 dither")
        if !result.success?
          puts "!!! Failed to convert #{ input } : #{ output }"
          puts result.success_result
          puts result.error_result
          puts result.result
          raise "Failed to convert #{ input }"
        end
      end
    end
  end
end

base_path = File.expand_path(File.dirname(__FILE__))

loader = Loader.new(base_path: base_path, card_path: ARGV[0])

puts "Starting from #{ base_path }"

# print "  Creating input folder... "
# loader.setup_input
# puts "✅"

print "  Creating output folder... "
loader.setup_output
puts "✅"

print "  Checking setup... "
loader.check
puts "✅"

puts "  Converting..."
loader.buttons.each do |button|
  puts "    Processing #{ button.name }... "
  button.files.each do |file|
    print "      Converting #{ file.name }... "
    file.convert
    puts "✅"
  end
end

if loader.load_card?
  print "  Loading card at #{ loader.paths.card_path }... "
  loader.load_card
  puts "✅"
end

puts "Done"
