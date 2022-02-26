require 'fileutils'
require 'shellwords'

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require 'tmpdir'
    source_paths.unshift(tempdir = Dir.mktmpdir('windstarter-'))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      '--quiet',
      'https://github.com/randikabanura/windstarter.git',
      tempdir
    ].map(&:shellescape).join(' ')

    if (branch = __FILE__[%r{windstarter/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def rails_6_or_newer?
  Gem::Requirement.new('>= 6.0.0.alpha').satisfied_by? rails_version
end

def add_gems
  unless IO.read('Gemfile') =~ /^\s*gem ['"]cssbundling-rails['"]/
    gem 'cssbundling-rails'
  end

  gem 'devise', '~> 4.8', '>= 4.8.0'
  gem 'friendly_id', '~> 5.4'
  gem 'jsbundling-rails'
  gem 'name_of_person', '~> 1.1'
  gem 'pundit', '~> 2.1'
  gem 'sidekiq', '~> 6.2'
  gem 'sitemap_generator', '~> 6.1'
  gem 'whenever', require: false
  gem 'responders', github: 'heartcombo/responders', branch: 'main'
  gem 'tailwindcss-rails'
  insert_into_file 'Gemfile', "\tgem 'annotate'\n", after: "group :development do\n"
  uncomment_lines 'Gemfile', /gem "redis"/
  comment_lines 'Gemfile', /gem "importmap-rails"/
end

def set_application_name
  # Add Application Name to Config
  environment 'config.application_name = Rails.application.class.module_parent_name'

  # Announce the user where they can change the application name in the future.
  puts 'You can change application name inside: ./config/application.rb'
end

def add_users
  route "root to: 'home#index'"
  generate 'devise:install'

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: 'development'
  generate :devise, 'User', 'first_name', 'last_name'
  # generate 'devise:views'

  if Gem::Requirement.new('> 5.2').satisfied_by? rails_version
    gsub_file 'config/initializers/devise.rb', /  # config.secret_key = .+/, '  config.secret_key = Rails.application.credentials.secret_key_base'
  end
end

def add_authorization
  generate 'pundit:install'
end

def add_jsbundling
  rails_command 'javascript:install:esbuild'
end

def copy_templates
  insert_into_file 'Procfile.dev', "worker: bundle exec sidekiq\n", after: "web: bin/rails server -p 3000\n"

  copy_file 'Procfile', force: true
  copy_file '.foreman', force: true

  directory 'app', force: true
  directory 'config', force: true

  route "get '/terms', to: 'home#terms'"
  route "get '/privacy', to: 'home#privacy'"
end

def add_sidekiq
  environment 'config.active_job.queue_adapter = :sidekiq'

  insert_into_file 'config/routes.rb',
                   "require 'sidekiq/web'\n\n",
                   before: 'Rails.application.routes.draw do'
end

def set_database_credentials
  username = ask("Please enter a database username:", "\e[34m", default: "username")
  password = ask("Please enter a database password:", "\e[34m", default: "password")

  insert_into_file 'config/database.yml', "\n  username: #{username}\n  password: #{password}\n", after: 'encoding: unicode'
end

def run_db_functions
  if yes?("Do you want to run database creation and migration (y/yes)?", "\e[31m")
    if yes?("Do you want to create database forcefully (y/yes)?", "\e[31m")
      rails_command 'db:drop'
    end
    rails_command 'db:create'
    rails_command 'db:migrate'
  end
end

def add_whenever
  run 'wheneverize .'
end

def add_friendly_id
  generate 'friendly_id'
  insert_into_file( Dir['db/migrate/**/*friendly_id_slugs.rb'].first, '[5.2]', after: 'ActiveRecord::Migration')
end

def add_sitemap
  rails_command 'sitemap:install'
end

def add_tailwind
  rails_command 'css:install:tailwind'
end

def add_annotate
  rails_command 'generate annotate:install'
end

unless rails_6_or_newer?
  puts 'Please use Rails 6.0 or newer to create a Windstarter application'
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  add_users
  add_authorization
  add_jsbundling
  add_sidekiq
  add_friendly_id
  add_tailwind
  add_annotate
  add_whenever
  add_sitemap
  rails_command 'active_storage:install'

  copy_templates

  set_database_credentials
  run_db_functions

  # Commit everything to git
  unless ENV['SKIP_GIT']
    git :init
    git add: '.'
    # git commit will fail if user.email is not configured
    begin
      git commit: %( -m 'Initial commit' )
    rescue StandardError => e
      puts e.message
    end
  end

  say
  say 'Windstarter app successfully created!', :blue
  say
  say 'To get started with your new app:', :green
  say "  cd #{original_app_name}"
  say
  say '  # Update config/database.yml with your database credentials'
  say
  say '  rails db:create db:migrate'
  say '  gem install foreman'
  say '  bin/dev'
end
