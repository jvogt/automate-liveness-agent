# frozen_string_literal: true
org_name      = attribute("org_name", description: "The organization name")
host          = attribute("host", description: "The data collector host")
port          = attribute("port", description: "The data collector port")
root_url      = "http://#{host}:#{port}/organizations/#{org_name}"
reset_url     = "#{root_url}/reset-pings"
ping_url      = "#{root_url}/pings"
kitchen_dir   = attribute("kitchen_dir", default: "/tmp/kitchen")
windows       = attribute("windows", default: false)
macos         = attribute("macos", default: false)
client_rb     = File.join(kitchen_dir, "test-client.rb")
stable_attrs  = File.join(kitchen_dir, "test-stable-attrs.json")
current_attrs = File.join(kitchen_dir, "test-current-attrs.json")
sleep_seconds = attribute("sleep_seconds", default: "10")
sleep_cmd     = "sleep #{sleep_seconds}"
log_file_path = "/var/log/chef/automate-liveness-agent/automate-liveness-agent.log"
stable_cmd    =
  if windows
    "$env:CHEF_RUN_INTERVAL=1 ; c:\\opscode\\chef\\bin\\chef-client.bat -z -c #{client_rb} -j #{stable_attrs}"
  elsif macos
    # The macos images have an older chef client built in so we have to specify
    # the full path
    "INTERVAL=2 /opt/chef/embedded/bin/chef-client -z -c #{client_rb} -j #{stable_attrs}"
  else
    "INTERVAL=2 chef-client -z -c #{client_rb} -j #{stable_attrs}"
  end
current_cmd   =
  if windows
    "$env:CHEF_RUN_INTERVAL=1 ; c:\\opscode\\chef\\bin\\chef-client.bat -z -c #{client_rb} -j #{current_attrs}"
  elsif macos
    # The macos images have an older chef client built in so we have to specify
    # the full path
    "INTERVAL=2 /opt/chef/embedded/bin/chef-client -z -c #{client_rb} -j #{current_attrs}"
  else
    "INTERVAL=2 chef-client -z -c #{client_rb} -j #{current_attrs}"
  end

control "setup-001" do
  desc "setup"
  title "converge previous stable version. if this fails while testing a bugfix it could be normal."

  describe command(stable_cmd) do
    its("exit_status") { should eq(0) }
  end
end

control "test-001" do
  desc "converge"
  title "upgrade by converging the compiled recipe artifact"

  describe command(current_cmd) do
    its("exit_status") { should eq(0) }
  end
end

control "setup-002" do
  desc "setup"
  title "reset the automate ping counter"

  describe http(reset_url, enable_remote_worker: false) do
    its("status") { should cmp 200 }
    its("body") { should cmp "0" }
  end
end

control "setup-003" do
  desc "wait"
  title "sleep to let the liveness agent send some pings"

  describe command(sleep_cmd) do
    its("exit_status") { should eq(0) }
  end
end

control "test-002" do
  desc "verify pings"
  title "verify that the pings count has increased"

  describe http(ping_url, enable_remote_worker: false) do
    its("body") { should_not cmp "0" }
    its("status") { should eq(200) }
  end
end

control "test-003" do
  desc "verify re-convergence"
  title "verify that the recipe can converge again without error"

  describe command(current_cmd) do
    its("exit_status") { should eq(0) }
  end
end

control "test-004" do
  desc "verify logging"
  title "verify that the agent is logging correctly"

  only_if { ! windows }

  describe file(log_file_path) do
    it { should be_file }
    it { should be_owned_by "chefautomate" }
    it { should be_readable }
    its("content") { should match(/201 Created/) }
  end
end
