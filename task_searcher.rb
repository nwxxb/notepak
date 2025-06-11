require 'ripgrep'
require 'json'
require 'thor'
require 'colorize'

class NotepakCLI < Thor
  check_unknown_options!

  desc 'list PATH', 'list all markdown\'s checkboxes from given PATH (dir or file)'
  option :status, type: :string, enum: %w[done todo all],
                  desc: 'checkboxes status, "all" will select all checkboxes',
                  default: 'todo'
  option :only_dated, type: :boolean, default: false,
                      desc: 'only select all checkboxes that contain date in it\'s content'
  def list(path = '.')
    if File.file?(path)
      target_path = path
    elsif File.directory?(path)
      if path == '/' && no?("I don't think given path '#{path}' is a note folder, do you want to continue? [y/n]")
        return 0
      end

      target_path = path
    else
      puts 'something wrong happen'
      return 1
    end

    status_char = []
    status_char << ' ' if %w[todo all].include?(options[:status])
    status_char << 'xX' if %w[done all].include?(options[:status])
    status_char = status_char.uniq.join

    # YYYY MM DD
    date_regex_group_def = if options[:only_dated]
                             '?<date>(\d{4}(?<delimiter>[\-\/\.])\d{1,2}(?&delimiter)\d{1,2})+'
                           else
                             '?<date>(\d{4}(?<delimiter>[\-\/\.])\d{1,2}(?&delimiter)\d{1,2})*'
                           end

    Ripgrep.run do
      # rubocop:disable Layout/LineLength
      regex_pattern = format('(?<checkbox>^- \[(?<status>[%<checkbox_status>s])\] [^\r\n]+(?:\n)*)(?<subcheckbox>^[ \t]+- \[(?&status)\] [^\r\n]+(?:\n)*)*(?<subcheckboxwithdate>^[ \t]+- \[(?&status)\] [^\r\n]*(%<date_regex_group_def>s)[^\r\n]*(?:\n)*)+(?&subcheckbox)*|(?<checkboxwithdate>^- \[(?&status)\] [^\r\n]*(?&date)[^\r\n]*(?:\n)*)(?&subcheckbox)*', checkbox_status: status_char, date_regex_group_def: date_regex_group_def)
      # rubocop:enable Layout/LineLength
      result = rg '--json', '--pcre2', '--type=md', '-U', regex_pattern, target_path
      matches = result.matches.map do |raw_match|
        JSON.parse(raw_match.raw_line)
      end
      matches = matches.select do |raw_obj|
        raw_obj['type'] == 'match'
      end
      matches = matches.map do |parsed_match_obj|
        init_line_number = parsed_match_obj.fetch('data').fetch('line_number')
        raw_line = parsed_match_obj.fetch('data').fetch('lines').fetch('text')
        lines = raw_line.lines.map.with_index do |line, idx|
          {
            'text' => line,
            'line_number' => init_line_number + idx
          }
        end

        {
          'path' => parsed_match_obj.fetch('data').fetch('path').fetch('text'),
          'submatches' => lines
        }
      end

      matches.each do |match|
        is_path_printed = false
        match.fetch('submatches').each do |submatch|
          text = submatch.fetch('text').rstrip
          next if text.empty?

          if text.match?(/^-/) && !is_path_printed
            puts "#{match.fetch('path')} (line #{submatch.fetch('line_number')})".colorize(:light_blue)
            is_path_printed = true
          end

          puts text
        end
        puts
      end
    end
  end
end

NotepakCLI.start(ARGV)
