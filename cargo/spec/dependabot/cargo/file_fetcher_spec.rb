# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Cargo::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:json_header) { { "content-type" => "application/json" } }
  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }
  before do
    stub_request(:get, url + "Cargo.toml?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cargo_manifest.json"),
        headers: json_header
      )

    stub_request(:get, url + "Cargo.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cargo_lockfile.json"),
        headers: json_header
      )
  end

  context "with a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_lockfile.json"),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and Cargo.lock" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Cargo.lock Cargo.toml))
    end
  end

  context "without a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "fetches the Cargo.toml" do
      expect(file_fetcher_instance.files.map(&:name)).
        to eq(["Cargo.toml"])
    end

    it "provides the Rust channel" do
      expect(file_fetcher_instance.ecosystem_versions).to eq({
        package_managers: { "cargo" => "default" }
      })
    end
  end

  context "with a rust-toolchain file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_toolchain.json"),
          headers: json_header
        )

      stub_request(:get, url + "rust-toolchain?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: JSON.dump({ content: Base64.encode64("nightly-2019-01-01") }),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and rust-toolchain" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Cargo.toml rust-toolchain))
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.ecosystem_versions }.to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "with a rust-toolchain.toml file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_toolchain.json").gsub("rust-toolchain", "rust-toolchain.toml"),
          headers: json_header
        )

      stub_request(:get, url + "rust-toolchain.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: JSON.dump({ content: Base64.encode64("[toolchain]\nchannel = \"1.2.3\"") }),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and rust-toolchain" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Cargo.toml rust-toolchain))
    end

    it "provides the Rust channel" do
      expect(file_fetcher_instance.ecosystem_versions).to eq({
        package_managers: { "cargo" => "1.2.3" }
      })
    end
  end

  context "with a path dependency" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: parent_fixture, headers: json_header)
    end
    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_path_deps.json")
    end

    context "that is fetchable" do
      before do
        stub_request(:get, url + "src/s3/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, body: path_dep_fixture, headers: json_header)
      end
      let(:path_dep_fixture) do
        fixture("github", "contents_cargo_manifest.json")
      end

      it "fetches the path dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Cargo.toml src/s3/Cargo.toml))
        expect(file_fetcher_instance.files.last.support_file?).
          to eq(true)
      end

      context "with a trailing slash in the path" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_path_deps_trailing_slash.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
        end
      end

      context "with a blank path" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_path_deps_blank.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml))
        end
      end

      context "for a target dependency" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_target_path_deps.json"
          )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
        end
      end

      context "for a replacement source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_replacement_path.json")
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
        end
      end

      context "for a patched source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_patched_path.json")
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
        end
      end

      context "when a git source is also specified" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps_alt_source.json")
        end

        before do
          stub_request(:get, url + "gen/photoslibrary1/Cargo.toml?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 200, body: path_dep_fixture, headers: json_header)
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml gen/photoslibrary1/Cargo.toml))
        end
      end

      context "with a directory" do
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "gocardless/bump",
            directory: "my_dir/"
          )
        end

        let(:url) do
          "https://api.github.com/repos/gocardless/bump/contents/my_dir/"
        end
        before do
          stub_request(:get, "https://api.github.com/repos/gocardless/bump/" \
                             "contents/my_dir?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_cargo_without_lockfile.json"),
              headers: json_header
            )
        end

        it "fetches the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
          expect(file_fetcher_instance.files.map(&:path)).
            to match_array(%w(/my_dir/Cargo.toml /my_dir/src/s3/Cargo.toml))
        end
      end

      context "and includes another path dependency" do
        let(:path_dep_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps.json")
        end

        before do
          stub_request(:get, url + "src/s3/src/s3/Cargo.toml?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_cargo_manifest.json"),
              headers: json_header
            )
        end

        it "fetches the nested path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(
              %w(Cargo.toml src/s3/Cargo.toml src/s3/src/s3/Cargo.toml)
            )
        end
      end
    end

    context "that is not fetchable" do
      before do
        stub_request(:get, url + "src/s3/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
        stub_request(:get, url + "src/s3?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
        stub_request(:get, url + "src?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
      end

      it "raises a PathDependenciesNotReachable error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::PathDependenciesNotReachable) do |error|
            expect(error.dependencies).to eq(["src/s3/Cargo.toml"])
          end
      end

      context "for a replacement source" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_replacement_path.json")
        end

        it "raises a PathDependenciesNotReachable error" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::PathDependenciesNotReachable) do |error|
              expect(error.dependencies).to eq(["src/s3/Cargo.toml"])
            end
        end
      end

      context "when a git source is also specified" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_path_deps_alt_source.json")
        end

        before do
          stub_request(:get, url + "gen/photoslibrary1/Cargo.toml?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404, headers: json_header)
          stub_request(:get, url + "gen/photoslibrary1?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404, headers: json_header)
          stub_request(:get, url + "gen?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404, headers: json_header)
        end

        it "ignores that it can't fetch the path dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml))
        end
      end
    end
  end

  context "with a workspace dependency" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: parent_fixture, headers: json_header)
    end
    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_root.json")
    end

    context "that is fetchable" do
      before do
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, body: child_fixture, headers: json_header)
      end
      let(:child_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_child.json")
      end

      it "fetches the workspace dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Cargo.toml lib/sub_crate/Cargo.toml))
      end

      context "and specifies the dependency implicitly" do
        let(:parent_fixture) do
          fixture("github", "contents_cargo_manifest_workspace_implicit.json")
        end
        before do
          stub_request(:get, url + "src/s3/Cargo.toml?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 200, body: child_fixture, headers: json_header)
        end

        it "fetches the workspace dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml src/s3/Cargo.toml))
          expect(file_fetcher_instance.files.map(&:support_file?)).
            to match_array([false, false])
        end
      end

      context "and specifies the dependency as a path dependency, too" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_workspace_and_path_root.json"
          )
        end

        it "fetches the workspace dependency's Cargo.toml" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Cargo.toml lib/sub_crate/Cargo.toml))
          expect(file_fetcher_instance.files.map(&:support_file?)).
            to match_array([false, false])
        end
      end
    end

    context "that is not fetchable" do
      before do
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
        # additional requests due to submodule searching
        stub_request(:get, url + "lib/sub_crate?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
        stub_request(:get, url + "lib?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "that is in a submodule" do
      before do
        # This file doesn't exist because sub_crate is a submodule, so returns a 404
        stub_request(:get, url + "lib/sub_crate/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404, headers: json_header)
        # This returns type: submodule, we're in the common submodule logic now
        stub_request(:get, url + "lib/sub_crate?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_submodule.json"))
        # Attempt to find the Cargo.toml in the submodule's repo.
        submodule_root = "https://api.github.com/repos/runconduit/conduit"
        stub_request(:get, submodule_root + "/contents/?ref=453df4efd57f5e8958adf17d728520bd585c82c9").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_without_lockfile.json"))
        # Found it, so download it!
        stub_request(:get, submodule_root + "/contents/Cargo.toml?ref=453df4efd57f5e8958adf17d728520bd585c82c9 ").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, headers: json_header, body: fixture("github", "contents_cargo_manifest.json"))
      end

      it "places the found Cargo.toml in the correct directories" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Cargo.toml lib/sub_crate/Cargo.toml))
        expect(file_fetcher_instance.files.map(&:path)).
          to match_array(%w(/Cargo.toml /lib/sub_crate/Cargo.toml))
      end
    end

    context "that specifies a directory of packages" do
      let(:parent_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_root_glob.json")
      end
      let(:child_fixture) do
        fixture("github", "contents_cargo_manifest_workspace_child.json")
      end
      let(:child_fixture2) do
        # This fixture also requires the first child as a path dependency,
        # so we're testing whether the first child gets fetched twice here, as
        # well as whether the second child gets fetched.
        fixture("github", "contents_cargo_manifest_workspace_child2.json")
      end

      before do
        stub_request(:get, url + "packages?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_cargo_packages.json"),
            headers: json_header
          )
        stub_request(:get, url + "packages/sub_crate/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, body: child_fixture, headers: json_header)
        stub_request(:get, url + "packages/sub_crate2/Cargo.toml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200, body: child_fixture2, headers: json_header)
      end

      it "fetches the workspace dependency's Cargo.toml" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(Cargo.toml
               packages/sub_crate/Cargo.toml
               packages/sub_crate2/Cargo.toml)
          )
        expect(file_fetcher_instance.files.map(&:type).uniq).
          to eq(["file"])
      end

      context "with a glob that excludes some directories" do
        let(:parent_fixture) do
          fixture(
            "github",
            "contents_cargo_manifest_workspace_root_partial_glob.json"
          )
        end
        before do
          stub_request(:get, url + "packages?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_cargo_packages_extra.json"),
              headers: json_header
            )
        end
      end
    end
  end

  context "with another workspace that uses excluded dependency" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: parent_fixture, headers: json_header)

      stub_request(:get, url + "member/Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: member_fixture, headers: json_header)

      stub_request(:get, url + "excluded/Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 200, body: member_fixture, headers: json_header)
    end
    let(:parent_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_root.json")
    end
    let(:member_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_member.json")
    end
    let(:excluded_fixture) do
      fixture("github", "contents_cargo_manifest_workspace_excluded_dependencies_excluded.json")
    end

    it "uses excluded dependency as a support file" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Cargo.toml member/Cargo.toml excluded/Cargo.toml))
      expect(file_fetcher_instance.files.map(&:support_file?)).
        to match_array([false, false, true])
    end
  end

  context "with a Cargo.toml that is unparseable" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_manifest_unparseable.json"),
          headers: json_header
        )
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  context "without a Cargo.toml" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_python.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
