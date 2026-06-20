require "open3"

class ImagePreprocessor
  # Resize so width AND height < 768 (use 767 cap) keeping aspect, convert greyscale.
  def self.process(input_dir:, output_dir:)
    inputs = Dir.glob(File.join(input_dir, "*.png")).sort
    inputs.map do |src|
      dest = File.join(output_dir, File.basename(src))
      cmd = ["magick", src, "-colorspace", "Gray", "-resize", "767x767>", dest]
      Rails.logger.debug("[Preprocess] #{cmd.join(' ')}")
      Open3.popen2e(*cmd) do |_in, out, wait|
        output = out.read
        raise "preprocess failed: #{output}" unless wait.value.success?
      end
      dest
    end
  end
end
