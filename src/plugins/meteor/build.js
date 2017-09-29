import { spawn } from 'child_process';
import archiver from 'archiver';
import fs from 'fs';
import debug from 'debug';
import { once } from 'lodash';

const log = debug('mup:module:meteor');

function buildApp(appPath, buildOptions, verbose, api) {
  // Check if the folder exists
  try {
    fs.statSync(api.resolvePath(appPath));
  } catch (e) {

    if (e.code === 'ENOENT') {
      console.log(`${api.resolvePath(appPath)} does not exist`);
    } else {
      console.log(e);
    }

    process.exit(1);
  }

  // Make sure it is a Meteor app
  try {
    // checks for release file since there also is a
    // .meteor folder in the user's home
    fs.statSync(api.resolvePath(appPath, '.meteor/release'));
  } catch (e) {
    console.log(`${api.resolvePath(appPath)} is not a meteor app`);
    process.exit(1);
  }

  return new Promise((resolve, reject) => {
    const callback = err => {
      if (err) {
        reject(err);

        // If there is an error building the app, exit.
        process.exit(1);
      }
      resolve();
    };
    buildMeteorApp(appPath, buildOptions, verbose, function(code) {
      if (code === 0) {
        archiveIt(buildOptions.buildLocation, api, callback);
        return;
      }
      console.log('\n=> Build Error. Check the logs printed above.');
      process.exit(1);
    });
  });
}

function buildMeteorApp(appPath, buildOptions, verbose, callback) {
  var executable = buildOptions.executable || 'meteor';
  var args = [
    'build',
    '--directory',
    buildOptions.buildLocation,
    '--architecture',
    'os.linux.x86_64'
  ];

  if (buildOptions.debug) {
    args.push('--debug');
  }

  if (buildOptions.mobileSettings) {
    args.push('--mobile-settings');
    args.push(JSON.stringify(buildOptions.mobileSettings));
  }

  if (buildOptions.serverOnly) {
    args.push('--server-only');
  } else if (!buildOptions.mobileSettings) {
    args.push('--mobile-settings');
    args.push(appPath + '/settings.json');
  }

  if (buildOptions.server) {
    args.push('--server');
    args.push(buildOptions.server);
  }

  if (buildOptions.allowIncompatibleUpdate) {
    args.push('--allow-incompatible-update');
  }

  var isWin = /^win/.test(process.platform);
  if (isWin) {
    // Sometimes cmd.exe not available in the path
    // See: http://goo.gl/ADmzoD
    executable = process.env.comspec || 'cmd.exe';
    args = ['/c', 'meteor'].concat(args);
  }

  var options = {
    cwd: appPath,
    env: {
      ...process.env,
      METEOR_HEADLESS: 1
    },
    stdio: verbose ? 'inherit' : 'pipe'
  };

  log(`Build Path: ${appPath}`);
  log(`Build Command:  ${executable} ${args.join(' ')}`);

  var meteor = spawn(executable, args, options);

  if (!verbose) {
    meteor.stdout.pipe(process.stdout, { end: false });
    meteor.stderr.pipe(process.stderr, { end: false });
  }

  meteor.on('error', e => {
    console.log(options);
    console.log(e);
    console.log('This error usually happens when meteor is not installed.');
  });
  meteor.on('close', callback);
}

function archiveIt(buildLocation, api, cb) {
  var callback = once(cb);
  var bundlePath = api.resolvePath(buildLocation, 'bundle.tar.gz');
  var sourceDir = api.resolvePath(buildLocation, 'bundle');

  var output = fs.createWriteStream(bundlePath);
  var archive = archiver('tar', {
    gzip: true,
    gzipOptions: {
      level: 9
    }
  });

  archive.pipe(output);
  output.once('close', callback);

  archive.once('error', function(err) {
    console.log('=> Archiving failed:', err.message);
    callback(err);
  });

  archive.directory(sourceDir, 'bundle').finalize();
}

module.exports = buildApp;
