
class IdentityDigest
  def self.digest(s)
    # Strip off the first character, it'll just be a \0 or \x1 anyway
    s[1..-1]
  end
end

# https://github.com/OpenZeppelin/merkle-tree?tab=readme-ov-file#standard-merkle-trees
def digest(m)
  IdentityDigest.digest(m)
end

def make_new_leaf(event)
  lineage = MerkleNode.push_leaf!(event)
  MerkleNode.untaint! event.session, IdentityDigest
end

SECP256K1 = Secp256k1::Context.create
# Fixed seed for test
KEY_PAIR = SECP256K1.key_pair_from_private_key(
  Secp256k1::Util.hex_to_bin("415ac5b1b9c3742f85f2536b1eb60a03bf64a590ea896b087182f9c92f41ea12")
)
SIGNER_PUBLIC_KEY = Secp256k1::Util.bin_to_hex(KEY_PAIR.public_key.compressed)

if ENV['NUM']
  NUM = ENV['NUM'].to_i
else
  NUM = 1000
end

def do_bm
  (1..NUM).to_a.map(&:to_s).each_with_index do |data, i|
    hashed_data = digest("\0" + data)
    signed_hashed_data = SECP256K1.sign_schnorr(KEY_PAIR, Digest::Keccak.digest(data, 256))
    timestamp = 1708758140 + i

    event = Event.create! signer: SIGNER_PUBLIC_KEY,
                          session: "CHAR",
                          data: data,
                          hashed_data: hashed_data,
                          signed_hashed_data: Secp256k1::Util.bin_to_hex(signed_hashed_data.serialized),
                          timestamp: timestamp
    Rails.logger.info "Created event #{data}"
    make_new_leaf(event)
    Rails.logger.info "Created leaf #{data}"
  end
  root = MerkleNode.root("CHAR")
end

namespace :benchmark do
  task :clear_log do 
    puts "Clearing log"
    path = Rails.root.join('log', 'development.log')
    `echo "" > #{path}`
  end

  task :clear_data do 
    puts "Clearing data, events and merkle_nodes"
    Event.delete_all
    MerkleNode.delete_all
  end

  task :get_insert_and_update_count_from_log do
    path = Rails.root.join('log', 'development.log')
    log = File.read(path)
    path2 = Rails.root.join('log', 'development.log.0')
    if File.exist?(path2)
      log += File.read(path2)
    end
    insert_count = log.scan(/INSERT /).count
    update_count = log.scan(/UPDATE /).count
    select_count = log.scan(/SELECT /).count
    puts "Insert count: #{insert_count}"
    puts "Update count: #{update_count}"
    puts "Select count: #{select_count}"
  end

  desc 'Benchmark for creating events and merkle_nodes'
  task bm: [:environment, :clear_data, :clear_log] do
    require 'benchmark'

    Benchmark.bm do |x|
      x.report("create #{NUM} events") do
        do_bm
      end
    end
  end
end


Rake::Task["benchmark:bm"].enhance do
  Rake::Task["benchmark:get_insert_and_update_count_from_log"].invoke
end
