Object subclass: #SCIAbstractLoadSpec
  ^ (aString asString 
    copyReplaceAll: (String with: Character cr with: Character lf) with: (String with: Character lf))
    copyReplaceAll: (String with: Character cr) with: (String with: Character lf)! !
  ^ ((aString asString 
    copyReplaceAll: '&' with: '&amp;') 
    copyReplaceAll: '"' with: '&quot;') 
    copyReplaceAll: '<' with: '&lt;'! !
  ^ aCollectionOfStrings do: [ :each | self runCategory: each ]! !
  ^ self runClasses: (self classesInCategory: aString) named: aString! !
  self subclassResponsibility! !
  self subclassResponsibility! !
  ^ aCollectionOfStrings collect: [ :each | self runPackage: each ]! !
  super initialize.
  suiteTime := 0 asDuration.
  suitePosition := suiteFailures := suiteErrors := 0.
  progressFile := StandardFileStream stdout
  ! !
  suite := aTestSuite! !
  "just close the file"
  [ progressFile close ] on: Error do: []! !
	[ 
      	self setUp.
      	suiteTime := [ self runAll ]
        		timeToRun ]
          			ensure: [ self tearDown ]! !
  suite tests do: [ :each | each run: self ]! !
  | error stack  |
  self 
    beginTestCase: aTestCase
    runBlock: [ [ [ aTestCase runCase ] 
      on: Halt , Error, TestFailure
      do: [ :err |
        error := err.
        aTestCase isExpectedFailure ifFalse: [self serializeError: error of: aTestCase].
        stack := self stackTraceString: err of: aTestCase ]]
      on: TestSkip do: [ :err| "nothing to do..." ] ].
    
  (error isNil or: [aTestCase isExpectedFailure])  ifFalse: [
    (error isKindOf: TestFailure)
      ifTrue: [ self writeError: error stack: stack ]
      ifFalse: [ self writeFailure: error stack: stack ]].
    
  self endTestCase! !
  "We got an error from a test, let's serialize it so we can properly debug it later on..."
  | context testCaseMethodContext |
  
  context := error signalerContext.
  testCaseMethodContext := context findContextSuchThat: [ :ctx| 
    ctx receiver == aTestCase and: [ ctx methodSelector == #performTest ]].
  context := context copyTo: testCaseMethodContext.
  
  [ FuelOutStackDebugAction
    serializeTestFailureContext: context sender     
    toFileNamed: aTestCase class name asString,'-', aTestCase selector, '.fuel' ] 
  on: Error 
  do: [:err| "simply continue..." ]

! !
  progressFile nextPutAll: 'running suite: ';
    nextPutAll: suite name ; crlf; flush.
    
  stream := StandardFileStream forceNewFileNamed: suite name , '-Test.xml'.
  stream := MultiByteFileStream newFrom: stream.
  stream nextPutAll: '<?xml version="1.0" encoding="UTF-8"?>'; lf.
  stream nextPutAll: '<testsuite name="'; nextPutAll: (self encode: suite name); 
    nextPutAll: '" tests="'; print: suite tests size; nextPutAll: '">'.
  
  "Now this is ugly. We want to update the time and the number of failures and errors, but still at the same time stream a valid XML. So remember this position and add some whitespace, that we can fill later."
  suitePosition := stream position - 1.
  stream nextPutAll: (String new: 100 withAll: $ ); lf.
  
  "Initialize the test resources."
  suite resources do: [ :each |
    each isAvailable
      ifFalse: [ each signalInitializationError ] ]! !
  suite resources 
    do: [ :each | each reset ].
    
  stream tab; nextPutAll: '<system-out><!![CDATA[]]></system-out>'; lf.
  stream tab; nextPutAll: '<system-err><!![CDATA[]]></system-err>'; lf.
  stream nextPutAll: '</testsuite>'.
  
  stream position: suitePosition.
  stream 
    nextPutAll: ' failures="'; print: suiteFailures; 
    nextPutAll: '" errors="'; print: suiteErrors; 
    nextPutAll: '" time="'; print: suiteTime / 1000.0; 
    nextPutAll: '">'.
  stream close.
  
  progressFile 
    nextPutAll: 'finished running suite: ';
    nextPutAll: suite name;
    close! !
  ^ suiteErrors! !
  ^ suiteFailures! !
  ^ self suiteTotal - self suiteFailures - self suiteErrors! !
  ^ suite 
    ifNotNil: [ suite tests size ]
    ifNil: [ 0 ]! !
  ^ suiteFailures ~= 0 or: [ suiteErrors ~= 0 ]! !
  | time |
  progressFile 
    nextPutAll: 'starting testcase: ' ; 
    nextPutAll: aTestCase class name; 
    nextPutAll:'>>';
    nextPutAll: aTestCase selector; 
    nextPutAll: ' ... '; 
    flush.
    
  time := aBlock timeToRun.
  stream tab; 
    nextPutAll: '<testcase classname="'; 
    nextPutAll: (self encode: (aTestCase class category copyReplaceAll: '-' with: '.')); 
    nextPut: $.; nextPutAll: (self encode: aTestCase class name); 
    nextPutAll: '" name="'; nextPutAll: (self encode: aTestCase selector); 
    nextPutAll: '" time="'; print: (time / 1000.0); 
    nextPutAll: '">'; lf
  
! !
  stream tab; nextPutAll: '</testcase>'; lf.
  progressFile nextPutAll: 'finished' ; crlf; flush.
! !
  ^ String streamContents: [ :str | 
    | context |
    context := err signalerContext.
    [ context isNil or: [ context receiver == aTestCase and: [ context methodSelector == #runCase ] ] ] whileFalse: [
      str print: context; lf.
      context := context sender ] ] ! !
  suiteErrors := suiteErrors + 1.
  stream tab; tab; nextPutAll: '<error type="'.
  self writeException: error stack: stack.
  stream nextPutAll: '</error>'; lf! !

  stream 
    nextPutAll: (self encode: error class name); 
    nextPutAll: '" message="'; nextPutAll: (self encode: (error messageText ifNil: [ error description ])); 
    nextPutAll: '">'; 
    nextPutAll: (self encode: stack).! !
  suiteFailures := suiteFailures + 1.
  stream tab; tab; nextPutAll: '<failure type="'.
  self writeException: error stack: stack.  
  stream  nextPutAll: '</failure>'; lf! !
  | suite classes |
  suite := TestSuite named: aString.
  classes := (aCollectionOfClasses
    select: [ :each | (each includesBehavior: TestCase) and: [ each isAbstract not ] ])
      asSortedCollection: [ :a :b | a name <= b name ].
  classes isEmpty
    ifTrue: [ ^ nil ].
  classes
    do: [ :each | each addToSuiteFromSelectors: suite ].
  ^ self runSuite: suite! !
  ^ self runClasses: (RPackage organizer packageNamed: aString) definedClasses named: aString! !
  ^ self new
    initializeOn: aTestSuite; 
    run;
    done! !