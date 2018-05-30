# Puppet AixAutomation #

#### Table of Contents

1. [Description](#description)
1. [Setup - The basics of getting started with aixautomation](#setup)
    * [What aixautomation affects](#what-aixautomation-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with aixautomation](#beginning-with-aixautomation)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)

## Description
 This aixautomation Puppet module has been developed against Puppet 5.3.3.<br>  
 This aixautomation Puppet module enables automation of software maintenance operations 
  on a list of LPARs from a NIM server on which Puppet runs. <br>
 Necessary updates are automatically downloaded from FixCentral using 'suma' 
  functionalities, and are locally kept and shared between LPARs if possible.<br>
 Updates can be automatically applied on a list of LPARs, through 'nim push' operation, 
  therefore everything runs from the NIM server, and nothing needs to be installed on 
  LPARs themselves.<br>
 Necessary efix are computed and retrieved using 'flrtvc', downloaded, kept locally and 
  shared between LPAR, then applied on a list of LPARs.

## Setup
### Setup Puppet 
 Download Puppet 5.3 from https://puppet.com/download-puppet-enterprise :<br> 
  **- for AIX 7.2,7.1** : https://s3.amazonaws.com/puppet-agents/2017.3/puppet-agent/5.3.5/repos/aix/7.1/PC1/ppc/puppet-agent-5.3.5-1.aix7.1.ppc.rpm<br>
  **- for AIX 6.1** : https://s3.amazonaws.com/puppet-agents/2017.3/puppet-agent/5.3.5/repos/aix/6.1/PC1/ppc/puppet-agent-5.3.5-1.aix6.1.ppc.rpm<br>
  After Puppet installation, path to puppet is /opt/puppetlabs/puppet/bin/puppet<br>
  Please note that Puppet comes with its own ruby, you'll find it here after Puppet installation :<br> 
    "/opt/puppetlabs/puppet/bin/ruby -version" returns "ruby 2.4.2p198 (2017-09-14 revision 59899)" 
  
### Setup aixautomation
 Module aixautomation (aixautomation.tar) needs to be untarred into 
  /etc/puppetlabs/code/environments/production/modules, which is the install directory.<br>
 All relative paths below are related to this 
  /etc/puppetlabs/code/environments/production/modules installation directory.<br>
  
 All aixautomation Puppet setups are done through the ./manifests/init.pp file.<br>
 As a prerequisites of aixautomation Puppet module, NIM configuration between NIM server
  (on which this Puppet module runs), and the LPARs (on which software maintenance 
  operations are performed) needs to be properly set : all LPARs which can either 
  not be accessible thru a simple 'ping -c1 -w5 <lpar>' command or thru a 
  simple 'c_rsh' command will be excluded from the list of targets on which 
  ./manifests/init.pp will be applied. <bt>
      
 List of lpars on which rules can be applied is retrieved thru NIM server by 
  getting list of standalones.<br>
 For advanced users who know 'ruby' language : if this list of standalones 
  is too large, and to spare time, you can skip some standalones by manually 
  editing ./aixautomation/lib/factor/standalones.rb : search for 'To shorten 
  execution', and use sample of code to perform the same logic.  
 
### What aixautomation affects 
 This module requires available disk space to store updates downloaded from FixCentral, 
  and to store downloaded eFix. By default downloads are performed into '/tmp', but a 
  more appropriate directory needs to be set into ./manifests/init.pp ('root' parameter 
  of 'download' clause). File system on which downloads are performed is automatically 
  increased (100 MB each time) if necessary (if system allows).<br>
 This module will perform software updates of your systems, and install (or remove) 
  eFix.  

### Setup Requirements 
 This module requires that the LPAR which are targeted to be updated are managed by 
  the same NIM server than the one on which Puppet runs.
 
### Beginning with aixautomation
 As a starter, you can only perform a status, which will display the 'oslevel -s' 
  result and 'lslpp -l' results of command on the list of LPAR you want to update. 
  
 As far as 'update' operation are concerned :<br> 
  You can perform download operations from FixCentral separately and see results.<br>
  You can update in preview mode only, just to see the results, and decide to apply 
   later on.
  
 As far as 'efix' operations are concerned :<br>
  You can perform all preparation steps without applying the efix ans see the results<br>
  You can choose to apply efix later on <br>
  You can remove all efix installed if necessary<br>
   
## Usage
 A large number of commented samples are provided in ./examples/init.pp, and should be 
  used as a starting point. <br>
 Puppet AixAutomation logs are generated into /tmp/PuppetAixAutomation.log.<br> 
  Up to 12 rotation log files of one 1 MB are kept : /tmp/PuppetAixAutomation.log.0
   to /tmp/PuppetAixAutomation.log.12<br>
 Puppet framework can be caught using --logdest parameter on the command line.<br>  
 
  As said already, module is installed into /etc/puppetlabs/code/environments/production/modules : 
   /etc/puppetlabs/code/environments/production/modules/aixautomation, and all relative paths below
   are relative to /etc/puppetlabs/code/environments/production/modules.<br>
  
  You can customize ./aixautomation/manifests/init.pp and 
     then apply it using following command lines :<br>
        puppet apply --noop --modulepath=/etc/puppetlabs/code/environments/production/modules -e "include aixautomation"<br>
     or : <br>
        puppet apply  --debug --modulepath=/etc/puppetlabs/code/environments/production/modules -e "include aixautomation"<br>
     or : <br>
        puppet apply --logdest=/tmp/PuppetApply.log --debug \
         --modulepath=/etc/puppetlabs/code/environments/production/modules -e "include aixautomation"<br>   
        If you use "--logdest" parameter, you won't see any output on the 
         command line as everything is redirected to log file.  
            

## Reference
### Facters
 Specific aixautomation facters collect the necessary data enabling 
  aixautomation module to run :<br> 
    - debug_level <br>
    - standalones : you'll find results on this factor into ./standalones.yml file.<br>
    - (preparation for) vios  : you'll find results on this factor into ./vios.yml file.<br> 
    - servicepacks : you'll find results on this factor into ./aixautomation/suma/sp_per_tl.yml file.<br>
 
### Custom types and providers
 Three custom type and their providers constitute the aixautomation module.<br>
 All custom-types are documented into ./examples/aixautomation.pp<br>
 
 #### Custom type : download (provider : suma)
 The aim of this provider is to provide download services using suma functionality.<br>
 Suma requests are generated so that updates are downloaded from Fix Central.<br>
 Suma metadata are downloaded if ever they are not locally present into './data/sp_per_tl.yml'  
  file : this file gives for each possible technical level the list of available service packs.<br> 
  It is a good practice to consider that the './data/sp_per_tl.yml' delivered is maybe
  not up-to-date, and therefore let 'suma' provider downloads metadata 'in live' 
  and compute last './data/sp_per_tl.yml'. To perform this, you can rename 
  './data/sp_per_tl.yml' to './data/sp_per_tl.yml.saved' so that this 'data/sp_per_tl.yml' 
  is computed again. <br>
 Various types of suma downloads can be performed : either "SP", or "TL", or "Latest" :<br>
  - "SP" contains everything update system on a given Technical Level.<br>
  - "TL" contains everything to update system from a Technical Level to another 
    Technical Level.<br>
  - "Latest" contains everything to update system to the last Service pack of a given 
    Technical Level.<br>
 
 #### Custom type : patchmngt (provider : nimpush)
 The aim of this provider is to provide software maintenance operations on a list of LPARs 
  using NIM push mode. Everything is performed from the NIM server on which this aixautomation 
  Puppet module runs.<br>   
 This NIM push mode can use suma downloads performed by Suma provider, as preliminary step.<br>
 Software maintenance operations include : install and updates<br>
    
 #### Custom type : fix (provider : flrtvc)
 The aim of this provider is to provide appropriate eFix installations using flrtvc functionality.<br> 
 "Root" parameter is used as download directory : tt should be an ad hoc file system dedicated to 
  download data, keep this file system separated from the system so prevent saturation.   
 List of appropriate eFix to be installed on a system is computed, and eFix are installed.<br>
 Several steps are necessary to achieve this efix installation task, and they are performed 
  following this order : "runFlrtvc", "parseFlrtvc", "downloadFixes", "checkFixes", 
  "buildResource", "installResource". <br>
 Executions can be stopped after any step, and this is controlled thru the 'to_step' parameter 
  into ./manifests/init.pp.<br>
 Each step persists its results into a yaml file, which can be found into 'root' directory 
  used for storing downloaded iFix.<br> 
 All yaml file can be reused between two execution, to spare time if ever the external 
  conditions have not changed, this is controlled thru the 'clean' parameter which needs 
  then to be set to 'no'. By default it is set to 'true'.<br>
 eFix are sorted by 'Packaging Date' before being applied, i.e. most recent first. It could 
  occur that one particular eFix prevents another one (less recent) from being installed if 
  they touch the same file.<br>      
        
## Limitations
 List of missing things to be documented.<br> 
 Refer to TODO.md<br>

## Development
 List of things to be done to be documented.<br> 
 Refer to TODO.md<br>

## Release Notes/Contributors/Etc. **Optional**
 Last changes to be documented. <br>
