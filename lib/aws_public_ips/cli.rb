# frozen_string_literal: true

require 'optparse'

module AwsPublicIps
  class CLI
    # Supported services:
    # EC2 (and as a result: ECS, EKS, Beanstalk, Fargate, Batch, & NAT Instances)
    # ELB (Classic ELB)
    # ELBv2 (ALB/NLB)
    # RDS
    # Redshift
    # APIGateway
    # CloudFront
    # Lightsail
    # ElasticSearch

    # Services that don't need to be supported:
    # S3 - all s3 buckets resolve to the same ip addresses
    # SQS - there's a single AWS-owned domain per region (i.e. sqs.us-east-1.amazonaws.com/<account_id>/<queue_name>)
    # NAT Gateways - these do not allow ingress traffic
    # ElastiCache - all elasticache instances are private. You can make one public by using a NAT instance with an EIP:
    # https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/accessing-elasticache.html#access-from-outside-aws
    # but NAT instances are EC2 machines, so this will be caught by the EC2 check.
    # DynamoDB - no public endpoints
    # SNS - no public endpoints
    # Elastic Transcoder - no public endpoints
    # Athena - no public endpoints

    # Services that maybe have public endpoints / still need testing:
    # fargate
    # amazonmq
    # directory service (AD)
    # emr
    # Directconnect
    # Kinesis
    # SES
    # https://aws.amazon.com/products/
    # AWS Neptune (still in preview / not GA yet)

    def all_services
      @all_services ||= Dir['lib/aws_public_ips/checks/*.rb'].map { |path| File.basename(path, '.rb') }.sort
    end

    def all_formats
      @all_formats ||= Dir['lib/aws_public_ips/formatters/*.rb'].map { |path| File.basename(path, '.rb') }.sort
    end

    def parse(args)
      options = {
        format: 'text',
        services: all_services,
        verbose: false
      }

      OptionParser.new do |opts|
        opts.banner = 'Usage: aws_public_ips [options]'

        opts.on('-s', '--services <s1>,<s2>,<s3>', Array, 'List of AWS services to check. Available services: ' \
          "#{all_services.join(',')}. Defaults to all.") do |services|
          services.map(&:downcase!).uniq!
          invalid_services = services - all_services
          raise ArgumentError, "Invalid service(s): #{invalid_services.join(',')}" unless invalid_services.empty?
          options[:services] = services
        end

        opts.on('-f', '--format <format>', String, 'Set output format. Available formats: ' \
          "#{all_formats.join(',')}. Defaults to text.") do |fmt|
          unless all_formats.include?(fmt)
            raise ArgumentError, "Invalid format '#{fmt}'. Valid formats are: #{all_formats.join(',')}"
          end
          options[:format] = fmt
        end

        opts.on('-v', '--[no-]verbose', 'Enable debug/trace output') do |verbose|
          options[:verbose] = verbose
        end
      end.parse(args)

      options
    end

    def check_service(service)
      require "aws_public_ips/checks/#{service}.rb"
      AwsPublicIps::Checks.const_get(service.capitalize).run
    end

    def output(formatter, results)
      require "aws_public_ips/formatters/#{formatter}.rb"
      formatter_klass = AwsPublicIps::Formatters.const_get(formatter.capitalize)
      output = formatter_klass.new(results).format
      puts output unless output.empty?
    end

    def run(args)
      options = parse(args)

      results = options[:services].map do |service|
        [service.to_sym, check_service(service)]
      end.to_h

      output(options[:format], results)
    rescue StandardError, Interrupt => ex
      puts ex.inspect
      puts ex.backtrace if options[:verbose]
      Process.exit(1)
    end
  end
end
