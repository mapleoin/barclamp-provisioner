# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

states = node["provisioner"]["dhcp"]["state_machine"]
tftproot=node["provisioner"]["root"]
pxecfg_dir="#{tftproot}/discovery/pxelinux.cfg"
nodes = search(:node, "crowbar_usedhcp:true")
admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
if not nodes.nil? and not nodes.empty?
  nodes.map{|n|Node.load(n.name)}.each do |mnode|
    Chef::Log.info("Testing if #{mnode[:fqdn]} needs a state transition")
    if mnode[:state].nil?
      Chef::Log.info("#{mnode[:fqdn]} has no current state!")
      next
    end
    new_group = states[mnode[:state]]

    mac_list = []
    mnode["network"]["interfaces"].each do |net, net_data|
      net_data.each do |field, field_data|
        next if field != "addresses"
        field_data.each do |addr, addr_data|
          next if addr_data["family"] != "lladdr"
          mac_list << addr unless mac_list.include? addr
        end
      end
    end
    mac_list.sort!
    admin_data_net = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mnode, "admin")
    nodeaddr = sprintf("%X",admin_data_net.address.split('.').inject(0){|acc,i|(acc<<8)+i.to_i})

    case
    when  new_group.nil? || new_group == "noop"
      Chef::Log.info("#{mnode[:fqdn]}: #{mnode[:state]} does not map to a DHCP state.")
      next
    when (new_group == "delete") || (new_group == "reset")
      Chef::Log.info("Deleting #{mnode[:fqdn]}")
      # Delete the node
      if new_group == "delete"
        system("knife node delete -y #{mnode.name} -u chef-webui -k /etc/chef/webui.pem")
        system("knife role delete -y crowbar-#{mnode.name.gsub(".","_")} -u chef-webui -k /etc/chef/webui.pem")
      end
      mac_list.each_index do |i|
        dhcp_host "#{mnode.name}-#{i}" do
          hostname mnode.name
          ipaddress "0.0.0.0"
          macaddress mac_list[i]
          action :remove
        end
        file "#{pxecfg_dir}/01-#{mac_list[i].gsub(':','-').downcase}" do
          action :delete
        end
      end
    when new_group == "execute"
      mac_list.each_index do |i|
        dhcp_host "#{mnode.name}-#{i}" do
          hostname mnode.name
          ipaddress admin_data_net.address
          macaddress mac_list[i]
          action :add
        end
        file "#{pxecfg_dir}/01-#{mac_list[i].gsub(':','-').downcase}" do
          action :delete
        end
      end
    else
      mac_list.each_index do |i|
        dhcp_host "#{mnode.name}-#{i}" do
          hostname mnode.name
          ipaddress admin_data_net.address
          macaddress mac_list[i]
          options [
                   'filename "discovery/pxelinux.0"',
                   "next-server #{admin_ip}"
                  ]
          action :add
        end
        if new_group == "os_install"
          # This eventaully needs to be conifgurable on a per-node basis
          os=node[:provisioner][:default_os]
          template "#{pxecfg_dir}/01-#{mac_list[i].gsub(':','-').downcase}" do
            mode 0644
            owner "root"
            group "root"
            source "default.erb"
            variables(:append_line =>  node[:provisioner][:available_oses][os][:append_line],
                      :admin_web => node[:provisioner][:available_oses][os][:webserver],
                      :install_name => node[:provisioner][:available_oses][os][:install_name],
                      :initrd => node[:provisioner][:available_oses][os][:initrd],
                      :kernel => node[:provisioner][:available_oses][os][:kernel])
          end
        else
          template "#{pxecfg_dir}/01-#{mac_list[i].gsub(':','-').downcase}" do
            mode 0644
            owner "root"
            group "root"
            source "default.erb"
            variables(:append_line => "#{node[:provisioner][:sledgehammer_append_line]} crowbar.state=#{new_group}",
                      :install_name => new_group,
                      :initrd => "initrd0.img",
                      :kernel => "vmlinuz0")
          end
        end
      end
    end
  end
end
