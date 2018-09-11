apt-get install unzip
pwd
ls -lt
wget "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" && unzip awscli-bundle.zip && ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
template_file=`grep template_file ci/config.yml | sed 's/template_file: *//;s/ *\"//;s/\".*//;'`;
timestamp=`echo $(($(date +%s%N)/1000000))`
account=`grep accountId ci/config.yml | sed 's/accountId: *//;s/ *\"//;s/\".*//;'`;
region=`grep region ci/config.yml | sed 's/region: *//;s/ *\"//;s/\".*//;'`;
cross_account_role=`grep cross_account_role ci/config.yml | sed 's/cross_account_role: *//;s/ *\"//;s/\".*//;'`;
cross_account_role=`echo $cross_account_role | tr -d '\\040\\011\\012\\015'`
template=`echo $template_file | tr -d '\\040\\011\\012\\015'`
accountId=`echo $account | tr -d '\\040\\011\\012\\015'`
stack_name=stack-$accountId-$timestamp
region=`echo $region | tr -d '\\040\\011\\012\\015'`
export AWS_DEFAULT_REGION=$1
export AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$2
export output_bucket=$3
export sns_topic=$4

aws cloudformation create-stack-set --stack-set-name ${stack_name}  --template-body file://templates/${template} >> /usr/local/message-${stack_name}.txt
aws cloudformation create-stack-instances --stack-set-name ${stack_name} --accounts ${accountId} --regions ${region} --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1  >> /usr/local/message-${stack_name}.txt

OperationId=`grep OperationId /usr/local/message-${stack_name}.txt | sed 's/"OperationId": *//;s/ *\"//;s/\".*//;'`;
StackSetId=`grep StackSetId /usr/local//message-${stack_name}.txt | sed 's/"StackSetId": *//;s/ *\"//;s/\".*//;q'`

aws cloudformation list-stack-set-operation-results --stack-set-name ${stack_name} --operation-id ${OperationId} > /usr/local/message.txt
Status=`grep Status /usr/local/message.txt | sed 's/"Status": *//;s/ *\"//;s/\".*//;'`;
until [ "$Status" = "SUCCEEDED" -o "$Status" = "FAILED" ] ; do sleep 5; aws cloudformation list-stack-set-operation-results --stack-set-name ${stack_name} --operation-id ${OperationId} > /usr/local/message.txt; cat /usr/local/message.txt; Status=`grep Status /usr/local/message.txt | sed 's/"Status": *//;s/ *\"//;s/\".*//;q'`; echo $Status; done
aws cloudformation describe-stack-instance --stack-set-name ${stack_name} --stack-instance-account ${accountId} --stack-instance-region ${region} >> /usr/local/message-${stack_name}.txt
StackId=`grep StackId /usr/local/message-${stack_name}.txt | sed 's/"StackId": *//;s/ *\"//;s/\".*//;'`;
aws sts assume-role --role-arn $cross_account_role --role-session-name RoleSession${stack_name} > /usr/local/assume-role-output.txt


AccessKeyId=`grep AccessKeyId /usr/local/assume-role-output.txt | sed 's/"AccessKeyId": *//;s/ *\"//;s/\".*//;'`;
SecretAccessKey=`grep SecretAccessKey /usr/local/assume-role-output.txt | sed 's/"SecretAccessKey": *//;s/ *\"//;s/\".*//;'`;
SessionToken=`grep SessionToken /usr/local/assume-role-output.txt | sed 's/"SessionToken": *//;s/ *\"//;s/\".*//;'`;

cat /usr/local/message-${stack_name}.txt
cat /usr/local/message.txt
echo $StackId
export AWS_ACCESS_KEY_ID=$AccessKeyId
export AWS_SECRET_ACCESS_KEY=$SecretAccessKey
export AWS_SESSION_TOKEN=$SessionToken

aws cloudformation list-stack-resources --stack-name $StackId --region ${region} > "/usr/local/output-${stack_name}.txt"

unset AWS_ACCESS_KEY_ID; unset AWS_SECRET_ACCESS_KEY; unset AWS_SESSION_TOKEN
aws s3api put-object --bucket ${output_bucket} --key Dev/output-${stack_name}.txt --body "/usr/local/output-${stack_name}.txt" --acl public-read
url="https://s3-$AWS_DEFAULT_REGION.amazonaws.com/${output_bucket}/Dev/output-${stack_name}.txt"
echo " The text file can be downloaded using the url: ${url} \n " >> "/usr/local/output-${stack_name}.txt"
aws sns publish --topic-arn ${sns_topic} --message file://"/usr/local/output-${stack_name}.txt"
echo "Stack Set id: $StackSetId\n " >> /usr/local/output-ops-${stack_name}.txt
echo "Stack id: $StackId\n " >> /usr/local/output-ops-${stack_name}.txt
cat /usr/local/output-${stack_name}.txt >> /usr/local/output-ops-${stack_name}.txt
aws s3api put-object --bucket ${output_bucket} --key Ops/output-ops-${stack_name}.txt --body "/usr/local/output-ops-${stack_name}.txt"


