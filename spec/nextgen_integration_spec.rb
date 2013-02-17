require 'spec_helper'
require 'tempfile'
require 'mail'

describe "Integrations" do
  class RailsApp
    def initialize(name, path)
      @name = name
      @path = File.expand_path("../railsapps/#{path}", __FILE__)
      reset
    end

    def to_s() @name end

    def read_email(mail_name)
      Mail.read_from_string run("puts Mailer.#{mail_name}.to_s")
    end

    def reset
      @extra_code = ""
    end

    def before_mail(code)
      @extra_code << "\n" << code << "\n"
    end

    private
    def run(code)
      Tempfile.open('code') do |file|
        file << @extra_code unless @extra_code.empty?
        file << code
        file.close
        IO.popen("cd #{@path.shellescape} && script/rails runner #{file.path.shellescape}").read
      end
    end
  end

  def parse_html_in_email(mail)
    Nokogiri::HTML.parse mail.html_part.body.decoded
  end

  [
    RailsApp.new("Rails 3.x", 'rails_30'),
  ].each do |app|
    before { app.reset }

    describe "with #{app}" do
      it "inlines styles for multipart emails" do
        email = app.read_email(:normal_email)

        email.to.should == ['example@example.org']
        email.from.should == ['john@example.com']
        email.should have(2).parts

        email.text_part.body.decoded.should_not match(/<.*>/)

        html = email.html_part.body.decoded
        html.should include '<!DOCTYPE'
        html.should include '<head'

        document = parse_html_in_email(email)
        document.should have_selector('body h1')
        document.should have_styling('background' => 'url(https://example.app.org/images/rails.png)').at_selector('.image')

        # If we deliver mails we can catch weird problems with headers being invalid
        email.delivery_method :test
        email.deliver
      end

      it "does not add headers for the roadie options and keeps custom headers in place" do
        email = app.read_email(:extra_email)
        email.header.fields.map(&:name).should_not include('css')
        email.header['X-Spam'].should be_present
      end

      it "only removes the css option when disabled" do
        app.before_mail %(
          Rails.application.config.roadie.enabled = false
        )

        email = app.read_email(:normal_email)

        email.header.fields.map(&:name).should_not include('css')

        email.to.should == ['example@example.org']
        email.from.should == ['john@example.com']
        email.should have(2).parts

        document = parse_html_in_email(email)
        document.should have_selector('body h1')
        document.should_not have_styling('background' => 'url(https://example.app.org/images/rails.png)').at_selector('.image')
      end
    end
  end
end