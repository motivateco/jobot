##
# Description
#   Monitor and dispatch build test failure on hudson
#
# Dependencies: 
#   none 
# 
# Configuration:
#   TODO process.env.HUDSON_TEST_MANAGER_URL
#   TODO process.env.HUDSON_TEST_MANAGER_ASSIGNMENT_TIMEOUT_IN_MINUTES=15
#   TODO process.env.HUDSON_TEST_MANAGER_DEFAULT_FIX_THRESHOLD_WARNING_HOURS=24
#   TODO process.env.HUDSON_TEST_MANAGER_DEFAULT_FIX_THRESHOLD_ESCALADE_HOURS=96
# 
# Commands: 
#   Broadcast failed tests for project {} to room {} - Tell Hubot to broadcast test results to the specified room.
#   Stop broadcasting failed tests for project {} to room {} - Tell Hubot to stop broadcast test results to the specified room.
#   Watch failed tests for project {} using build {} - Monitor tests for the specified build which is part of specified project.
#   Stop watching failed tests of build {} for project {} - Stop monitoring tests for the specified build which is part of specified project.
#
#   Set manager for project {} to {} - For security reason, must be sent in groupchat
#   Set {warning|escalade} test fix delay for project {} to {} {hour|day}(s) - Configure warning or escalade threshold. Accepted only if from project manager
#
#   Assign {1 | 1-4 | 1, 3 | com.eightd.some.test} (of project {}) to {me | someuser} - Assign a test/range/list of tests to a user
#   Show test report for project {}
#
# Notes: 
#   This plugin support multiple build for a project. This is usefull if multiple builds are working on the same project 
#   (same codebase/branch) but with different scope. This allows to avoid collision/test assignment duplication.
# 
# Author: 
#   Manuel Darveau
#

util = require( 'util' )
HudsonConnection = require( './hudson-test-manager/hudson_connection' )

routes = require( './hudson-test-manager/routes' )

class HudsonTestManager

  constructor: ( @robot ) ->
    unless process.env.HUDSON_TEST_MANAGER_URL
      @robot.logger.error 'HUDSON_TEST_MANAGER_URL not set'
      process.exit( 1 )

    @xmppIdResolver = require( './xmpp-id-resolver' )( @robot )
    @hudson = new HudsonConnection( process.env.HUDSON_TEST_MANAGER_URL )

    @backend = require( './hudson-test-manager/backend' )( @robot )

    #
    # Initial technological testing
    # TODO Remove this after initial tests
    #

    # TODO Remove this after initial tests
    robot.respond /.*status for (.*).*/i, ( msg ) =>
      jobName = msg.match[1]
      console.log "Build status requested for #{jobName}"
      hudson.getBuildStatus( jobName, @robot.http, ( err, data ) ->
        msg.reply( hudson.errorToString err ) if err
        msg.reply( "#{jobName} (build #{data.number}) is #{data.result}. See #{data.url}" ) if !err )

    # TODO Remove this after initial tests
    robot.respond /.*test report for (.*).*/i, ( msg ) =>
      jobName = msg.match[1]
      console.log "Test report requested for #{jobName}"
      msg.reply( "In progress..." )
      hudson.getTestReport( jobName, @robot.http, ( err, data ) =>
        if err
          msg.reply( hudson.errorToString err )
        else
          msg.reply( "Failed tests for #{data.jobName}" )
          for testcase in data.failedTests
            msg.reply( "#{testcase.url}" )
      )

    # TODO Remove this after initial tests
    # Example on how to resolve a groupchat message to a specific user message
    robot.respond /.*test ping me/i, ( msg ) =>
      sendPrivateMesssage( xmppIdResolver.getRealJIDFromGroupchatJID( msg.envelope.user.jid ), "Ping from #{@robot.name}" )

    #
    # Actual implementation
    #

    # Setup "routes":
    @setupRoutes( robot )

    # Setup watchdog
    setInterval( @.watchdog, 5 * 60 * 1000 )

  # TODO Add validations on ROOM for @conf... or add @conf... automatically  
  
  # Setup "jabber" routes
  setupRoutes: ( robot ) ->
    # Tell Hubot to broadcast test results to the specified room.
    robot.respond routes.BROADCAST_FAILED_TESTS_FOR_PROJETS_$_TO_ROOM_$, ( msg ) =>
      project = msg.match[1]
      room = msg.match[2]
      @backend.broadcastTestToRoom project, room
      msg.reply( "Will broadcast test failures of #{project} to room #{room}" )

    # Tell Hubot to stop broadcast test results to the specified room.
    robot.respond routes.STOP_BROADCASTING_FAILED_TESTS_FOR_PROJECT_$, ( msg ) =>
      project = msg.match[1]
      @backend.broadcastTestToRoom project, undefined
      msg.reply( "Won't broadcast test failures of #{project}" )

    # Monitor tests for the specified build which is part of specified project.
    robot.respond routes.WATCH_FAILED_TESTS_FOR_PROJECT_$_USING_BUILD_$, ( msg ) =>
      project = msg.match[1]
      build = msg.match[2]
      @backend.watchBuildForProject build, project
      msg.reply( "Will watch build #{build} in scope of #{project}" )

    # Stop monitoring tests for the specified build which is part of specified project.
    robot.respond routes.STOP_WATCHING_FAILED_TESTS_OF_BUILD_$_FOR_PROJECT_$, ( msg ) =>
      project = msg.match[1]
      build = msg.match[2]
      @backend.stopWatchingBuildForProject build, project
      msg.reply( "Won't watch build #{build} in scope of #{project} anymore" )

    # Set the project's manager
    robot.respond routes.SET_MANAGER_FOR_PROJECT_$_TO_$, ( msg ) =>
      # TODO For security reason, must be sent in groupchat
      project = msg.match[1]
      manager = msg.match[2]
      @backend.setManagerForProject manager, project
      msg.reply( "#{manager} in now manager of project #{project}" )

    # Configure warning or escalade threshold. Accepted only if from project manager
    robot.respond routes.SET_WARNING_OR_ESCALADE_TEST_FIX_DELAY_FOR_PROJECT_$_TO_$_HOURS_OR_DAY, ( msg ) =>
      level = msg.match[1]
      project = msg.match[2]
      amount = msg.match[3]
      unit = msg.match[4]
      @backend.setThresholdForProject project, level, amount, unit
      msg.reply( "#{manager} in now manager of project #{project}" )

    # Assign a test/range/list of tests to a user
    robot.respond routes.ASSIGN_TESTS_OF_PROJECT_$_TO_$_OR_ME, ( msg ) =>
      console.log "Not implemented"

    # Display failed test and assignee
    robot.respond routes.SHOW_TEST_REPORT_FOR_PROJECT_$, ( msg ) =>
      console.log "Not implemented"

  # Called when a new test result is available
  reportFailedTests: ( projectname, testResults ) ->
    # TODO Send the following to room:
    #   The following tests for project {} failed:
    #     1 - http...
    #     2 - http...


    # Notify which tests are not assigned. Can be used to send on demand, broadcast to room or escalade to manager
  notifyUnassignedTest: ( projectname, to_jid ) ->
    # TODO Update lastBroadcastId of unassigned tests in datastructure 
    # TODO Send to to_jid:
    # The following tests are still not assigned:
    #   1 - http...
    #   2 - http...

    # Notify of test fail past warning threshold
  notifyTestStillFail: ( projectname, to_jid ) ->
    # Failed tests for project {}:
    #- http://... is not assigned and fail since {failSinceDate}
    # or 
    #- http://... was assigned to {username | you} {x hours} ago

  watchdog: () ->
    # TODO Check for build status
    # TODO Check and notifyUnassignedTest() after env.HUDSON_TEST_MANAGER_ASSIGNMENT_TIMEOUT_IN_MINUTES minutes
    # TODO Check and notifyTestStillFail() if testfail past warning or escalade threshold

    # to_jid = 'mdarveau@jabber.8d.com'
  sendPrivateMesssage: ( to_jid, message ) ->
    envelope =
      room: to_jid
      user:
        type: 'chat'
    robot.send( envelope, message )

  # to_jid = 'room@conference.hostname'
  sendGroupChatMesssage: ( to_jid, message ) ->
    # TODO Validate if this works
    envelope =
      room: to_jid
      user:
        type: 'groupchat'
    robot.send( envelope, message )

module.exports = ( robot ) ->
  new HudsonTestManager( robot )