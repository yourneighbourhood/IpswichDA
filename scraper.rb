require 'scraperwiki'
require 'mechanize'

case ENV['MORPH_PERIOD']
  when /^([2][0][0-9][0-9][0|1][0-9])/
    if ( ENV['MORPH_PERIOD'][0..3].to_i > Date.today.year.to_i )
      ENV['MORPH_PERIOD'] = Date.today.year.to_s
      puts 'changing invalid year input'
    end

    month = ENV['MORPH_PERIOD'][4..5].to_i
    if ( month < 1 || month > 12 )
      ENV['MORPH_PERIOD'] = Date.today.year.to_s + Date.today.month.to_s
      puts 'changing invalid month input'
    end

    period = 'custom year and month: ' + ENV['MORPH_PERIOD']
    start_date = Date.new(ENV['MORPH_PERIOD'][0..3].to_i, ENV['MORPH_PERIOD'][4..5].to_i, 1)
    end_date   = Date.new(ENV['MORPH_PERIOD'][0..3].to_i, ENV['MORPH_PERIOD'][4..5].to_i + 1 , 1) - 1
  when 'lastmonth'
    period = 'lastmonth'
    start_date = (Date.today - Date.today.mday) - (Date.today - Date.today.mday - 1).mday
    end_date   = Date.today - Date.today.day
  when 'thismonth'
    period = 'thismonth'
    start_date = (Date.today - Date.today.mday + 1)
    end_date   = Date.today
  else
    period = (Date.today - 14).strftime("%d/%m/%Y")+'&2='+(Date.today).strftime("%d/%m/%Y")
    period = 'thisweek'
    start_date = Date.today - 14
    end_date   = Date.today
end

puts "Collecting data from " + period
# Scraping from Masterview 2.0

def scrape_page(page, comment_url)
  page.at("table.rgMasterTable").search("tr.rgRow,tr.rgAltRow").each do |tr|
    tds = tr.search('td').map{|t| t.inner_html.gsub("\r\n", "").strip}
    day, month, year = tds[2].split("/").map{|s| s.to_i}
    record = {
      "info_url" => (page.uri + tr.search('td').at('a')["href"]).to_s,
      "council_reference" => tds[1],
      "date_received" => Date.new(year, month, day).to_s,
      "description" => tds[3].gsub("&amp;", "&").split("<br>")[1].squeeze(" ").strip,
      "address" => tds[3].gsub("&amp;", "&").split("<br>")[0].gsub("\r", " ").squeeze(" ").strip,
      "date_scraped" => Date.today.to_s,
      "comment_url" => comment_url
    }
    #p record
    if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
      puts "Saving record " + record['council_reference'] + ", " + record['address']
      ScraperWiki.save_sqlite(['council_reference'], record)
    else
      puts "Skipping already saved record " + record['council_reference']
    end
  end
end

# Implement a click on a link that understands stupid asp.net doPostBack
def click(page, doc)
  href = doc["href"]
  if href =~ /javascript:__doPostBack\(\'(.*)\',\'(.*)'\)/
    event_target = $1
    event_argument = $2
    form = page.form_with(id: "aspnetForm")
    form["__EVENTTARGET"] = event_target
    form["__EVENTARGUMENT"] = event_argument
    form.submit
  else
    # TODO Just follow the link likes it's a normal link
    raise
  end
end

url = "http://pdonline.ipswich.qld.gov.au/pdonline/modules/applicationmaster/default.aspx"
comment_url = "mailto:plandev@ipswich.qld.gov.au"

agent = Mechanize.new

# Read in a page
page = agent.get(url)

form = page.forms.first
button = form.button_with(value: "I Agree")
form.submit(button)

(start_date..end_date).each do |date|
  query_period = "?page=found&5=T&6=F&1=" + start_date.strftime("%d/%m/%Y") + "&=" + start_date.strftime("%d/%m/%Y")

  puts "Date: " + start_date.to_s

  page = agent.get(url + query_period)
  current_page_no = 1
  next_page_link = true

  while next_page_link
    puts "Scraping page #{current_page_no}..."
    scrape_page(page, comment_url)

    page_links = page.at(".rgNumPart")
    if page_links
      next_page_link = page_links.search("a").find{|a| a.inner_text == (current_page_no + 1).to_s}
    else
      next_page_link = nil
    end
    if next_page_link
      current_page_no += 1
      page = click(page, next_page_link)
    end
  end

  start_date = start_date + 1
end
