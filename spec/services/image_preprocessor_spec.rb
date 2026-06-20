require "rails_helper"

RSpec.describe ImagePreprocessor do
  it "runs greyscale + resize for each image and returns outputs" do
    in_dir = Rails.root.join("tmp/spec_in"); out_dir = Rails.root.join("tmp/spec_out")
    FileUtils.mkdir_p(in_dir); FileUtils.mkdir_p(out_dir)
    File.write(in_dir.join("000.png"), "x"); File.write(in_dir.join("001.png"), "x")

    commands = []
    allow(Open3).to receive(:popen2e) do |*cmd, &blk|
      commands << cmd
      blk.call(nil, StringIO.new(""), double(value: double(success?: true)))
    end

    out = ImagePreprocessor.process(input_dir: in_dir, output_dir: out_dir)
    expect(out.size).to eq(2)
    expect(commands.first).to include("-colorspace", "Gray", "-resize", "767x767>")
  ensure
    FileUtils.rm_rf(in_dir); FileUtils.rm_rf(out_dir)
  end

  it "raises when magick fails" do
    in_dir = Rails.root.join("tmp/spec_in2"); out_dir = Rails.root.join("tmp/spec_out2")
    FileUtils.mkdir_p(in_dir); FileUtils.mkdir_p(out_dir)
    File.write(in_dir.join("000.png"), "x")
    allow(Open3).to receive(:popen2e) do |*_cmd, &blk|
      blk.call(nil, StringIO.new("bad"), double(value: double(success?: false)))
    end
    expect { ImagePreprocessor.process(input_dir: in_dir, output_dir: out_dir) }
      .to raise_error(RuntimeError, /preprocess failed/)
  ensure
    FileUtils.rm_rf(in_dir); FileUtils.rm_rf(out_dir)
  end
end
