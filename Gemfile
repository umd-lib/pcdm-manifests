source 'https://rubygems.org'

ruby '3.0.6'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.1.7', '>= 6.1.7.6'
# Use Puma as the app server
gem 'puma', '~> 5.6'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 3.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Http Client
gem 'faraday'
gem 'faraday_middleware'

# XML parsing
gem 'nokogiri'

# dotenv - For storing production configuration parameters
gem 'dotenv-rails'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platform: :mri
end

group :development do
  # Access an IRB console on exception pages or by using <%= console %> anywhere in the code.
  gem 'web-console', '>= 4.1.0'
  gem 'listen', '~> 3.3'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Code analysis tools
  gem 'rubocop', '= 1.14.0', require: false
  gem 'rubocop-rails', '= 2.10.1', require: false
  gem 'rubocop-checkstyle_formatter', require: false
  gem 'minitest-reporters', '~> 1.6'
end
