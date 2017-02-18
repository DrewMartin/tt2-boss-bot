require "rake/testtask"

task default: %w[test]

Rake::TestTask.new(:test) do |t|
  test_dir = File.expand_path('test')
  $LOAD_PATH.unshift(test_dir) unless $LOAD_PATH.include?(test_dir)

  t.libs << 'test'
  t.test_files = Dir['test/**/*_test.rb']
  t.verbose = true
end
