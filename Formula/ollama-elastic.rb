class OllamaElastic < Formula
  desc ""
  homepage ""
  version "dbeaea4"

  on_macos do
    url "https://github.com/elastic/ollama/releases/download/dbeaea4/ollama-darwin"
    sha256 "df241ff0b7f0f4ed3be36e2f9322848bd6b2a4dec205a84e0b104272a6393ffe"
    def install
      bin.install "ollama-darwin" => "ollama-elastic"
    end
  end

  on_linux do
    on_intel do
      if Hardware::CPU.is_64_bit?
        url "https://github.com/elastic/ollama/releases/download/dbeaea4/ollama-linux-amd64.tgz"
        sha256 "fa8429dccf0f484aab143e934cc3fa2ffb2d07519c62b380d3554d12ed5af6ec"

        def install
          bin.install "bin/ollama" => "ollama-elastic"
        end
      end
    end
    on_arm do
      if Hardware::CPU.is_64_bit?
        url "https://github.com/elastic/ollama/releases/download/dbeaea4/ollama-linux-arm64.tgz"
        sha256 "fc49eeeba27db672b1d56d91ccbe4f6ef853bc49162275d98f173e78ef1b1c48"

        def install
          bin.install "bin/ollama" => "ollama-elastic"
        end
      end
    end
  end
end
