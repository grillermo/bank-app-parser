require "rails_helper"

RSpec.describe ImageStitcher do
  it "invokes stitch.py with input dir and output path" do
    cmd_seen = nil
    allow(Open3).to receive(:popen2e) do |*cmd, &blk|
      cmd_seen = cmd
      blk.call(nil, StringIO.new("ok"), double(value: double(success?: true)))
    end

    out = ImageStitcher.stitch(input_dir: "/tmp/pre", output_path: "/tmp/out.png")
    expect(out).to eq("/tmp/out.png")
    expect(cmd_seen).to include("-i", "/tmp/pre", "-o", "/tmp/out.png")
    expect(cmd_seen.join(" ")).to include("stitch.py")
  end

  it "raises on failure" do
    allow(Open3).to receive(:popen2e) do |*_cmd, &blk|
      blk.call(nil, StringIO.new("crash"), double(value: double(success?: false)))
    end
    expect { ImageStitcher.stitch(input_dir: "/tmp/pre", output_path: "/tmp/out.png") }
      .to raise_error(RuntimeError, /stitch failed/)
  end
end
