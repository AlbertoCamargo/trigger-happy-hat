#  --- Methods ---
require 'Date'


# ----- Helpers Classes -----
class Constant
  # Those line should be environment variables
  ClIENT_ID = '03603a614ba82fe67a88'
  PASSWORD_SECRET = 'bb3fe7e0996bc1b50c484f023c89a242698072d0'

  AUTH_PARAMS = "&client_id=#{ClIENT_ID}&client_secret=#{PASSWORD_SECRET}"
  
  BASE_URL = 'https://api.github.com/'
  ORGANIZATION_URL = BASE_URL + 'orgs/'

  def self.repositories organization_name
    ORGANIZATION_URL + organization_name + '/repos'
  end

  def self.commits organization_name, repository
    BASE_URL + 'repos/' + organization_name + '/' + repository + '/commits'
  end

  def self.pagination page
    "?page=#{page}&per_page=100"
  end
end

class RESTfulService
  require 'net/https'
  require 'uri'
  require 'json'

  def self.make_request(url, default = false, page = 1, method = :get, params = '')
    uri = default ? URI.parse(url + Constant.pagination(page) + Constant::AUTH_PARAMS + params ) : URI.parse(url + Constant.pagination(page) + Constant::AUTH_PARAMS + params)
    http  = Net::HTTP.new(uri.host, uri.port)

    # Enable https requests
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    # request to github API
    response = http.get(uri.request_uri)
    raise "API rate limit exceeded, please try later" if response.code.to_i == 403
    
    response.code.to_i != 404 ? response : false
  end
end

# --------- Classes ---------- 
# ----- Bussiness Logic ------

class Fetcher

  def self.repositories response, repos
    
    unless response['link'].nil?
      next_page = response['link'].split(',').first
      data = fetch_pagination(next_page)
      
      if data[:rel] == 'next'
        repos = repos + JSON.parse(response.body)
        response = RESTfulService.make_request(data[:url], true)
        repositories(response, repos)
      else
        return repos + JSON.parse(response.body)
      end  
    end
    
    repos
  end

  def self.commits response, commits
    unless response['link'].nil?
      
      next_page = response['link'].split(',').first
      data = fetch_pagination(next_page)
      
      if data[:rel] == 'next'
        commits = commits + JSON.parse(response.body)
        response = RESTfulService.make_request(data[:url], true)
        commits(response, commits)
      else
        return commits + JSON.parse(response.body)
      end
    end
    
    commits
  end

  private
    def self.fetch_pagination header
      data = {}
      page = header.split(';')
      data[:url] = page[0].gsub(/<|>/, '')
      data[:rel] = page[1].gsub(/rel="|"/, '')

      data
    end
end

class Author
  attr_reader :name, :username
  attr_accessor :total_of_commits, :average_of_commits
  
  def initialize name, username
    @name = name
    @username = username
    @total_of_commits = 0
    @average_of_commits = 0
  end
end

class Commit
  attr_reader :sha, :user, :message, :date

  def initialize sha, user, message, date
    @sha = sha
    @user = user
    @message = message
    @date = date
  end
end

class Repository
  attr_reader :name, :description, :commits_url
  attr_writer :commits
  
  def initialize name, commits_url, description
    @name = name
    @description = description
    @commits_url = commits_url
    @commits = []
  end

  def add_commit commit
    @commits << commit
  end
end

class Organization
  attr_reader :name, :repositories
  attr_accessor :collaborators

  def initialize name
    @name = name
    @repositories = []
    @collaborators = []
  end

  def add_to_repos repo
    repositories << repo   
  end

  def add_collaborators collaborator
    @collaborators.push collaborator
  end

  def find_collaborator username
    @collaborators.detect { |collaborator| collaborator.username == username }
  end

  def fetch_commits since

    @repositories.each do |repository|
      puts "fetching commits of #{repository.name}..."
      repository.commits = []
      
      response = RESTfulService.make_request(repository.commits_url, false, 1, :get, "&since=#{DateTime.now - since.to_i}")
      commits = Fetcher.commits(response, JSON.parse(response.body))
      commits.each do |json_commit|
        # Parsing response
        next if json_commit['author'].nil?
        sha = json_commit['sha']
        author_name = json_commit['commit']['author']['name']
        username = json_commit['author']['login']
        committed_at = json_commit['commit']['author']['date']
        commit_message = json_commit['commit']['message']
        
        # Pushing commit in repository
        author = find_collaborator(username) || Author.new(author_name, username)
        author.total_of_commits += 1
        author.average_of_commits = (author.total_of_commits.to_f / since.to_f).round 2
        add_collaborators(author) if find_collaborator(username).nil?           
        
        commit = Commit.new(sha, author, commit_message, committed_at)
        repository.add_commit commit
      end
    end
  end

  def top_5
    @collaborators.sort { |a, b| a.average_of_commits <=> b.average_of_commits }.reverse[0..4]
  end

  def group_top_5
    container = []
    top_5.each_with_index do |collaborator, index|
      container << [index + 1, collaborator.average_of_commits]
    end
    container
  end
end

#  --- Main ---


class GUI
  require 'ascii_charts'
  require 'console_view_helper'

  def draw_histogram top_5

    puts AsciiCharts::Cartesian.new(top_5, :bar => true, :hide_zero => true).draw
  end

  def company_menu
    puts 'Type your company'
    print '>> '
    company = gets.chomp
  end

  def menu
    puts "\n1. Trigger happy hat"
    puts '2. Set period'
    puts '3. Quit'
    print '>> '
    option = gets.chomp
  end

  def set_days_ago
    puts 'Set period'
    print '>> '
    period = gets.chomp
    puts "set up correctly\n"
    period
  end
end

gui = GUI.new
company_valid = false
$organization = nil

begin
  company_name = gui.company_menu
  $organization = Organization.new(company_name)
  
  puts "fetching repositories of #{$organization.name}..."
  if response = RESTfulService.make_request(Constant.repositories($organization.name))
    repositories = Fetcher.repositories(response, JSON.parse(response.body))
    repositories.each do |repository|
      repo_name = repository['name']
      commits_url = Constant.commits($organization.name, repo_name)
      repository = Repository.new(repo_name, commits_url, repository['description'])
      $organization.add_to_repos(repository)
    end
    company_valid = true
  else
    puts "Company not found. Please try again \n\n"
  end
end while(!company_valid)

puts "\n"

quit = false
$days_ago = nil

while !quit
  option = gui.menu
  
  case option
    when '1'
      if $days_ago.nil?
        puts 'You must set up the period first!'
        $days_ago = gui.set_days_ago
        $organization.fetch_commits($days_ago)
      end
      
      if top5 = $organization.group_top_5
        gui.draw_histogram top5
        top5_users = $organization.top_5
        usernames = top5_users.map { |user| user.username }
        total_of_commits = top5_users.map { |user| user.total_of_commits.to_s }
        average_of_commits = top5_users.map { |user| user.average_of_commits.to_s }

        puts ConsoleViewHelper.table([(1..top5_users.size).to_a.map { |e| e.to_s }, usernames, total_of_commits, average_of_commits], header: ['POSITION', 'USERNAME', 'TOTAL OF COMMITS', 'AVERAGE OF COMMITS'], cell_width: 25)
      else
        puts 'No commits founds :('
      end
    when '2'
      $days_ago = gui.set_days_ago
      $organization.fetch_commits($days_ago)
      # p $organization.
    when '3'
      quit = true
      break;
  end
end