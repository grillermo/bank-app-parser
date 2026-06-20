require "open3"

class ImageStitcher
  PYTHON = Rails.root.join("python_env/bin/python").to_s
  SCRIPT = Rails.root.join("vendor/image-stitch/stitch.py").to_s

  def self.stitch(input_dir:, output_path:)
    cmd = [PYTHON, SCRIPT, "-i", input_dir.to_s, "-o", output_path.to_s]
    Rails.logger.debug("[Stitch] #{cmd.join(' ')}")
    Open3.popen2e(*cmd) do |_in, out, wait|
      output = out.read
      raise "stitch failed: #{output}" unless wait.value.success?
      Rails.logger.debug("[Stitch] #{output}")
    end
    output_path.to_s
  end
end
